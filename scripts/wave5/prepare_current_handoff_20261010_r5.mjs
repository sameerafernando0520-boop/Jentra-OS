// NEW handoff for an actually completed final-r5 publication.
// Default check is read-only. Root alone may --write two absent artifacts.
// No source, image, SDK, native input, acceptance store, private or live operation.
import {lstat,open,realpath,writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {root,base,sha,eq,must,parse,inside,bytes,exists} from './desktop_verification_inputs_20261010_r5.mjs';
import {publicationPaths,livingPaths,acceptedIds,falseGates,publisherPath,auditPublishedFinalStatus} from './update_current_verification_status_20261010_r5_guarded.mjs';
import {finalPaths,recheckFinalSource} from './final_verification_inputs_20261010_r5.mjs';

const self='scripts/wave5/prepare_current_handoff_20261010_r5.mjs';
const publisherSha='1f9f6701974459afbb87589794c0058a399cc74072058071c7802da70199c73e';
const p={handoff:'docs/development/wave5-next-session-20261010-r5.md',index:base+'current-handoff-20261010-r5.json',publication:base+'current-handoff-publication-20261010-r5.json',
  originalReview:base+'complete-app-runtime-review-20261009.json',r13Review:base+'complete-app-runtime-review-20261009-r13.json',
  newReview:base+'complete-app-runtime-review-20261010-r5.json',newReviewMd:base+'complete-app-runtime-review-20261010-r5.md',
  composer:'scripts/wave5/prepare_current_runtime_review_20261010_r5.mjs'};
const originalPin={path:p.originalReview,sha256:'3af2dc69e77c37b939cdd02e27860261e36899b95aa68016b0f0703970de565f',bundleSha256:'13ffe2fdfd412fae36d3ff08c1f33bb59d9de85f20b2707e77ba6b9629eae83e'};
const r13Pin={path:p.r13Review,sha256:'97c0d0d29b706b1d1283e2408e4ed9b9622b1ef0a4ab2ddae8dec099fe5cf208',bundleSha256:'92a68a58d70a1f9061776be1b6416b8124112577b0a0859ed6f389becc2533d4'};

async function main(){
  const args=process.argv.slice(2);must(args.length<=1&&args.every(arg=>arg==='--write'),'FINAL_HANDOFF_ARGUMENT_INVALID');const publish=args.includes('--write');
  const missing=[];for(const file of [publicationPaths.before,publicationPaths.after,...livingPaths,publisherPath,...[originalPin,r13Pin].map(ref=>ref.path),p.composer])if(!await exists(file))missing.push(file);
  const SDKJobActive=await exists('build/wave5-flutter-job.lock'),probe=await exists(publicationPaths.after)?parse(await bytes(root,publicationPaths.after)):null;
  if(missing.length||SDKJobActive||probe?.status!=='complete'){
    console.log(JSON.stringify({readyForHandoff:false,missing,SDKJobActive,finalPublicationStatus:probe?.status??'absent',outputsWritten:false,SDKJobsExecuted:false}));if(publish)process.exitCode=1;return;
  }
  const a=await auditPublishedFinalStatus(),{bound,bind,json,matrix,evidence:e}=a;await bind(publisherPath,publisherSha);
  const current=a.after.evidence;
  for(const pin of [originalPin,r13Pin]){const record=await json(pin.path,pin.sha256),{bundleSha256,...body}=record;
    must(bundleSha256===pin.bundleSha256&&sha(Buffer.from(JSON.stringify(body)))===bundleSha256&&record.ownerApproved===false&&record.projectId==='xpdoufauvrbdmxgngetv'&&
      record.migrations.length===71&&new Set(record.migrations.map(row=>row.path)).size===71&&record.migrations.every(row=>row.installed===false),'EXACT_UNAPPROVED_ORIGINAL_RUNTIME_SCOPE_REQUIRED');}
  must(matrix.ownerAcceptedCriteria===3&&eq(matrix.ownerCriterionAcceptance.criterionIds,acceptedIds)&&current.ownerAcceptedCriteria===3&&current.remainingUnacceptedCriteria===106&&
    current.currentR5PendingVerificationPreserved===true&&current.fullDesktopMatchingBase.passed===2010&&current.fullDesktopMatchingBase.failed===0&&current.fullDesktopMatchingBase.skipped===0&&
    eq(current.actualNativePreview.counts,e.counts)&&current.workerAdapter.testsRerun===false&&current.accounting.reexecutedInR5===false,'EXACT_ACTUAL_FINAL_HANDOFF_STATE_REQUIRED');
  for(const key of falseGates)must(matrix[key]===false,'HANDOFF_SEPARATE_GATE_CHANGED:'+key);
  await bind(p.composer,'d670915fbac08136b15d0896ee060df477928fb039b3f5ddf27d68091bd2a124');await bind(self);
  const now=new Date().toISOString(),link=(label,to)=>`[${label}](<${path.relative(path.dirname(p.handoff),to).split(path.sep).join('/')}>)`,native=current.actualNativePreview,resume=current.additionalReadOnlyLiveObservation;
  const handoffText='# Jentra OS — current r5 continuation\n\n'+
    `Prepared at ${now}. The 20261010 r5 file and product labels identify the retained revision. Workspace: C:\\Users\\sheha\\Desktop\\Jentra OS. Supabase project: xpdoufauvrbdmxgngetv. **Jentra OS remains incomplete.**\n\n`+
    'First read '+link('the actual final status publication',publicationPaths.after)+', '+link('its originals, guards and planned bytes',publicationPaths.before)+', '+link('the current requirement matrix',publicationPaths.matrix)+', '+link('the living status',publicationPaths.status)+', '+
    link('the exact approved source',finalPaths.source)+', '+link('paired ordinary build/package evidence',finalPaths.paired)+', '+link('the actual native Preview report',finalPaths.nativeMd)+', '+link('the worker adapter',finalPaths.worker)+
    ', '+link('the frozen full live preflight',finalPaths.live)+' and '+link('the separate narrow resume read',resume.record.path)+'. Read every status, review, verification and contract referenced by these records before relying on a completion claim.\n\n'+
    'Owner acceptance remains exactly **3/109**: AC-551, AC-552 and AC-553. The other **106 criteria remain open**. All 109 requirement rows, statements, specification lines, evidence mappings and direct decisions are preserved, together with currentR5PendingVerification and the r3 historical checkpoint. Delegated tests create no additional owner acceptance.\n\n'+
    'The original 83-image owner decision and promotion are retained. A separate direct decision approved exactly the eight later Preview guidance images, bundle SHA-256 `'+current.candidateBundleSha256+'`; their guarded promotion retained the original bytes. The postapproval source has 1,068 inputs, exactly five declared Dart changes and six new behavior tests. '+
    link('The genuine complete full desktop SDK run',finalPaths.full)+` passed **2,010/0/0**, with every unique identity and all 83 approved image comparisons verified, finished at **${e.desktop.finishedAt}**. Its matching source SHA-256 is \`${current.sourceManifest.sha256}\`. It was not rerun after the overnight resume.\n\n`+
    link('The current paired Windows adapter',finalPaths.paired)+` binds Preview and Connected ordinary lib/main.dart builds with exactly three runner identity overlays per copy, **${e.releaseCount} release entries** and **${e.inputs.packageFiles.length} portable entries**, including every copied and decoded ZIP byte. `+
    'The complete suite ran once in the approved verification tree; the Windows identity copies were not a second full-suite execution. '+link('The portable Windows package',current.zip.path)+' has SHA-256 `'+current.zip.sha256+'`. Packaging checkpoint nativeLaunched=false remains preserved.\n\n'+
    link('The subsequent actual offline Preview session',finalPaths.nativeMd)+` captured **${native.cases} closed cases** and **${native.screenshots} screenshots**: **${native.counts.pass} pass / ${native.counts.fail} fail / ${native.counts.blocked} blocked**. `+
    `Failed IDs: ${native.failedCaseIds.join(', ')||'none'}. Blocked IDs: ${native.blockedCaseIds.join(', ')||'none'}. Started at ${native.startedAt}; finished at ${native.finishedAt}. `+
    'The exact returned process/window/product identities and actual screenshot bytes are bound. Input-tool documentation/version dates remain separate from the product SDK, earlier full suite and builds. These Preview observations authenticate no account, post no transaction and close no full authenticated keyboard or owner gate. '+
    link('The before/after product-directory observations',finalPaths.postStorage)+' inspect existence of exactly four isolated paths; no credentials, sessions, path contents or existing acceptance stores were read or copied.\n\n'+
    'The earlier 75/8 strict image comparison remains a failed historical control. The r3 2,004-case suite, builds and 10-pass/2-fail/2-blocked Preview session remain dated predecessor evidence. The r4 cache-permission failure, pending periodic auth timer, duplicate/incomplete cases and exact owned tester interruption remain retained as failures. Do not substitute them for current r5 results or discard their failure evidence.\n\n'+
    'The **528/0/0** controlled accounting checks retain their earlier logs and 38 exact files. Domain/platform source inputs and the dependency lock are unchanged; the full desktop source changed and these checks were **not rerun as r5**. Actual user transactions, posting and authoritative report acceptance remain open. The **26 worker files** and **14/8-file payloads** remain unchanged; the **71 controlled tests** and **two Deno checks** retain their original r14 observations, with **no new delivery, deployment or model call** inferred.\n\n'+
    link('The frozen full r5 live metadata',finalPaths.live)+` observed **43 migrations / 107 API functions** at **${e.live.observedAt}**, with 120 unchanged providers, 15 enabled/forced RLS tables, 14 zero exact collision counters and the six exact installed ledger entries preserved. `+
    link('The separate narrow resume observation',resume.record.path)+` observed **43/107** at **${resume.observedAt}**, reread all 43 ledger rows, retained the same two Edge metadata objects and matched one enabled public key without printing values. `+
    'It did not rehash providers or repeat RLS/access/collision or trial-account queries. Refresh complete live state immediately before relying on a runtime contract. **Do not reinstall the six approved Wave 5 migrations or replay their source filenames.** Hosting remains the existing Supabase project.\n\n'+
    'Preserve desktop-test-20261009@jentra.invalid and the existing account. The prior owner-created login is separate historical evidence; current authenticated native acceptance remains open, and trial-account membership was not queried in the narrow resume read. Use private owner Auth Admin access for any necessary account action. Never fabricate auth.users rows or request, expose or log passwords/MFA codes. Permanent deletion requires explicit confirmation of the exact account.\n\n'+
    'Next, run the frozen current runtime composer in check mode, then compose its new source-bound review only when every guard passes: `node scripts/wave5/prepare_current_runtime_review_20261010_r5.mjs check`, followed by `compose`. This handoff satisfies that composer prerequisite; it does not assert that the new review has already been composed. '+
    link('The new runtime review',p.newReviewMd)+' and its machine manifest, when present, require a separate direct owner decision on their exact bundle SHA. The original `13ffe2fdfd412fae36d3ff08c1f33bb59d9de85f20b2707e77ba6b9629eae83e` and r13 `92a68a58d70a1f9061776be1b6416b8124112577b0a0859ed6f389becc2533d4` reviews remain preserved and unapproved. Image approvals and the three process criteria authorize no runtime installation.\n\n'+
    'The proposed runtime scope remains 71 ordered additional migrations excluding the installed six, private real Auth actors, same-project workers/receivers and bounded synthetic delivery/model/contention/load. After required approval and immediate preflight, execute genuine MFA, authenticated native checks, governed export download/reopen, persistent actual worker delivery and trusted model usage, independent-session contention, target-scale load and owner acceptance. Keep implementation, installed SQL, authenticated native, actual delivery, contention/load and direct owner acceptance as separate gates. All those remaining gates, full native keyboard and whole-system signoff remain false. Production and real billing remain excluded.\n\n'+
    'Continue every unblocked provider, cash-date, scenario/recovery, governed-export, persistent-worker and trusted-model implementation or investigation with agents. Use Superpowers, Plugin Management and connected Supabase tools where appropriate. Root alone serializes heavy Flutter jobs; record actual source hashes, SDK exits, analysis, tests, builds and renders after any source edit. No agent should invoke a simultaneous SDK job.\n\n'+
    'Preserve concurrent Wave 3/4 and Employee changes, acceptance stores and sessions. Do not reset, clean, broadly stage, commit or push. Do not copy acceptance-store contents into verification trees. Publish subsequent status changes only through guarded successors that retain original/current bytes and every requirement decision.\n';
  const handoffBytes=Buffer.from(handoffText),index={kind:'actual-current-r5-handoff',revision:'r5',preparedAt:now,sourceManifest:current.sourceManifest,
    finalPublication:bound.get(publicationPaths.after),finalBefore:bound.get(publicationPaths.before),publisher:bound.get(publisherPath),generator:bound.get(self),
    handoff:{path:p.handoff,sha256:sha(handoffBytes),bytes:handoffBytes.length},currentLivingDocuments:livingPaths.map(file=>bound.get(file)),ownerAcceptedCriteria:3,unacceptedCriteria:106,
    approvedGoldenFailures:0,laterApprovedImages:8,originalApprovedImages:83,candidateBundleSha256:current.candidateBundleSha256,fullDesktopCounts:{passed:2010,failed:0,skipped:0},fullDesktopFinishedAt:e.desktop.finishedAt,
    currentNativeCounts:e.counts,currentNativeScreenshots:e.screenshotCount,historicalAccountingPassedTests:528,workerTestsRerun:false,accountingTestsRerun:false,
    frozenFullLiveObservedAt:e.live.observedAt,additionalNarrowLiveObservation:resume,refs:[...bound.values()],evidence:current,
    SDKJobsExecuted:false,liveOperations:false,acceptanceStoresTouched:false,livingDocumentsChanged:false,ownerAcceptanceChanged:false,newRuntimeApproved:false,
    boundary:'A new handoff for an actually completed guarded publication. It grants no runtime or criterion decision and claims no future operation.'};
  const indexBytes=Buffer.from(JSON.stringify(index,null,2)+'\n'),outputs=new Map([[p.handoff,handoffBytes],[p.index,indexBytes]]);
  async function recheck(){must(!await exists('build/wave5-flutter-job.lock'),'SDK_ACTIVE_DURING_FINAL_HANDOFF');for(const ref of bound.values())must(sha(await bytes(root,ref.path))===ref.sha256,'CONCURRENT_FINAL_HANDOFF_INPUT_DRIFT:'+ref.path);
    const source=await recheckFinalSource(e);return{...source,finalPublication:bound.get(publicationPaths.after),ownerAcceptedCriteria:3,separateGatesPreserved:true};}
  await recheck();
  if(!publish){console.log(JSON.stringify({readyForHandoff:true,write:false,ownerAcceptedCriteria:3,unacceptedCriteria:106,fullDesktopCounts:{passed:2010,failed:0,skipped:0},fullDesktopFinishedAt:e.desktop.finishedAt,
    nativeCounts:e.counts,sourceManifest:current.sourceManifest,finalPublication:bound.get(publicationPaths.after),plannedOutputs:[...outputs].map(([path,raw])=>({path,sha256:sha(raw),bytes:raw.length})),
    publication:p.publication,outputsWritten:false,SDKJobsExecuted:false}));return;}
  for(const file of [...outputs.keys(),p.publication])must(!await exists(file),'NEW_FINAL_HANDOFF_OUTPUT_REQUIRED:'+file);
  for(const folder of ['docs/development',base.slice(0,-1)]){const full=inside(root,folder);must(await realpath(full)===full&&!(await lstat(full)).isSymbolicLink(),'FINAL_HANDOFF_OUTPUT_PARENT_LINK_REFUSED');}
  const journal=await open(inside(root,p.publication),'wx');await journal.writeFile(JSON.stringify({kind:'current-r5-handoff-reserved',revision:'r5',startedAt:now,finalPublication:bound.get(publicationPaths.after),fullPublication:false,
    plannedOutputs:[...outputs].map(([path,raw])=>({path,sha256:sha(raw),bytes:raw.length})),boundary:'Reserved before writing; interruption never establishes a complete handoff.'},null,2)+'\n');await journal.sync();
  const written=[],observed=[];let failure=null,finalAudit=null;
  try{for(const [file,raw]of outputs){await recheck();await writeFile(inside(root,file),raw,{flag:'wx'});written.push(file);}finalAudit=await recheck();}catch(error){failure={message:error.message,code:error.code??null};}
  for(const [file,raw]of outputs)try{const actual=await bytes(root,file);observed.push({path:file,sha256:sha(actual),bytes:actual.length,matchesPlanned:sha(actual)===sha(raw)&&actual.length===raw.length});}catch(error){observed.push({path:file,error:error.message});}
  if(observed.some(row=>row.matchesPlanned!==true))failure??={message:'ACTUAL_FINAL_HANDOFF_OUTPUT_DRIFT',code:null};const fullPublication=written.length===2&&failure===null&&finalAudit!==null;
  const result={kind:'current-r5-handoff-publication-result',revision:'r5',finishedAt:new Date().toISOString(),status:fullPublication?'complete':'failed',fullPublication,writtenOutputs:written,observedOutputs:observed,failure,finalSourceAudit:finalAudit,
    finalPublication:bound.get(publicationPaths.after),generator:bound.get(self),validatedInputs:[...bound.values()],ownerAcceptedCriteria:3,fullDesktopPassedTests:2010,currentNativeCounts:e.counts,
    SDKJobsExecuted:false,liveOperations:false,acceptanceStoresTouched:false,livingDocumentsChanged:false,ownerAcceptanceChanged:false,newRuntimeApproved:false,
    boundary:'Only two new handoff artifacts were attempted. Living documents, approved images, stores and acceptance remain unchanged; actual partial output is retained.'};
  try{await journal.truncate(0);await journal.write(JSON.stringify(result,null,2)+'\n',0,'utf8');await journal.sync();}finally{await journal.close();}
  console.log(JSON.stringify({status:result.status,fullPublication,writtenOutputs:written,failure,publication:p.publication,ownerAcceptedCriteria:3,fullDesktopPassedTests:2010,nativeCounts:e.counts,SDKJobsExecuted:false,livingDocumentsChanged:false}));if(!fullPublication)process.exitCode=1;
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))await main();
