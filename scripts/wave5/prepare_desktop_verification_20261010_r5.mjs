// NEW r5 variant. Preserved r4 predecessor scripts/wave5/prepare_desktop_verification_20261010_r4.mjs SHA-256 6546e48cf3628b4713606f97965387697bfb440df2b9cf86b67a78b5e2a2075e.
// New r5 evidence preparation only. Default check is read-only; no SDK process.
// Freeze creates absent, exact source copies and immutable manifests. It never
// replaces an approved image, copies application state, or rewrites old evidence.
import {constants} from 'node:fs';
import {copyFile,lstat,mkdir,readFile,realpath,writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {sources} from './cash_ui_evidence.mjs';
import {
  root,base,sourcePath,approvedSourcePath,preparerPath,helperPath,runnerPath,
  oldSourcePath,oldRunPath,oldCandidatePath,ownerPath,promotionPath,
  declaredDartPaths,newTestIdentities,declaredGoldenFailures,resolutionPaths,supportPaths,
  sdk,flutter,scope,sha,eq,mapEq,must,parse,inside,bytes,exists,selected,
  execution,stageDefinitions,auditInputs,auditStage,stagePath,auditR4History,
} from './desktop_verification_inputs_20261010_r5.mjs';

const priorSourceSha='2d055695358df8a3d4b69b551747539800caa8ea70b6d89def6227446da87289';
const priorRunSha='bfb55910e1c35d8b33f9a327bac3ecf34696d55e4d12afed27260e0561fa93cb';
const priorOwnerPath=base+'owner-golden-decision-20261010-r2.json';
const priorPromotionPath=base+'golden-promotion-result-20261010-r2.json';
const oldWarm=path.join(root,'build/w5goldens20261010/r1');
const scriptPaths=[preparerPath,helperPath,runnerPath,'scripts/wave5/cash_ui_evidence.mjs',
  'scripts/wave5/accounting_execution_verifier_20261010_r3.mjs',
  'scripts/wave5/run_accounting_checks_20261010_r2.mjs','scripts/wave5/record_continuation_windows.mjs'];
const boundary='Frozen source and local controlled verification preparation only. All 83 earlier approvals, existing accounts, source lock and acceptance stores remain preserved. No installed SQL, authenticated native, MFA, actual delivery/model use, independent sessions, load, owner acceptance, production or billing is inferred. Four SDK files and cached resolution/support are pinned; hosted package bodies are not independently audited file by file.';

async function binders(){
  const bound=new Map();
  const read=async(p,h)=>{
    const b=await bytes(root,p),actual=sha(b);
    must((!h||h===actual)&&(!bound.has(p)||bound.get(p).sha256===actual),'BOUND_R5_PREPARATION_INPUT_DRIFT:'+p);
    bound.set(p,{path:p,sha256:actual});return b;
  };
  const json=async(p,h)=>parse(await read(p,h));
  const finish=async()=>{for(const b of bound.values())must(sha(await bytes(root,b.path))===b.sha256,'INPUT_CHANGED_DURING_R5_PREPARATION:'+b.path);};
  return{bound,read,json,finish};
}

async function toolPins(toolchain){
  must(eq(toolchain?.tooling?.map(t=>t.path),['C:/src/flutter/bin/cache/flutter.version.json',sdk,flutter,'C:/src/flutter/bin/cache/artifacts/engine/windows-x64/flutter_tester.exe']),'EXACT_FOUR_PRIOR_SDK_PINS_REQUIRED');
  for(const t of toolchain.tooling)must(sha(await readFile(t.path))===t.sha256,'CURRENT_R5_SDK_DRIFT:'+t.path);
  const metadata=parse(await readFile(toolchain.tooling[0].path));
  must(eq(metadata,toolchain.sdkMetadata)&&metadata.frameworkVersion==='3.47.5'&&metadata.dartSdkVersion==='3.13.4','CURRENT_R5_SDK_METADATA_DRIFT');
  return{sdkMetadata:metadata,tooling:toolchain.tooling.map(t=>({...t}))};
}

async function cachedInputs(tree){
  const read=async paths=>{
    const result=[];for(const p of paths)result.push({path:p,sha256:sha(await bytes(tree,p))});return result;
  };
  const resolution=await read(resolutionPaths),cachedSupport=await read(supportPaths);
  const config=parse(await bytes(tree,resolutionPaths[0]));
  must(config.configVersion===2&&Array.isArray(config.packages)&&new Set(config.packages.map(p=>p.name)).size===config.packages.length,'CACHED_PACKAGE_CONFIGURATION_INVALID');
  const baseUrl=new URL('file:///'+tree.replaceAll('\\','/')+'/.dart_tool/package_config.json');
  for(const member of scope){
    const name=(await bytes(tree,member+'/pubspec.yaml')).toString('utf8').match(/^name:\s*([a-z0-9_]+)\s*$/m)?.[1];
    const entry=config.packages.find(p=>p.name===name);
    must(entry&&path.resolve(fileURLToPath(new URL(entry.rootUri,baseUrl)))===path.join(tree,member),'CACHED_WORKSPACE_PACKAGE_ESCAPES:'+member);
  }
  const workspace=parse(await bytes(tree,supportPaths[0]));
  must(typeof workspace.workspaceRoot==='string'&&path.resolve(tree,'.dart_tool/pub',workspace.workspaceRoot)===tree,'CACHED_WORKSPACE_REFERENCE_ESCAPES');
  return{resolution,cachedSupport};
}

async function initialAudit(){
  const b=await binders(),old=await b.json(oldSourcePath,priorSourceSha),run=await b.json(oldRunPath,priorRunSha),candidate=await b.json(oldCandidatePath);
  must(old.kind==='postapproval_desktop1068_source_manifest'&&old.selectedSources===1068&&Object.keys(old.sourceHashes??{}).length===1068&&old.snapshot===oldWarm&&old.sourceInputsSha256===sha(Buffer.from(JSON.stringify(old.sourceHashes))),'APPROVED_1068_BASE_REQUIRED');
  must(run.status==='complete'&&run.stage==='approvedAll'&&run.fullSuitePassed===true&&run.exitCode===0&&run.integrityError===null&&run.spawnError===null&&
    eq(run.counts,{passed:2004,failed:0,skipped:0})&&eq(run.sourceManifest,{path:oldSourcePath,sha256:priorSourceSha})&&eq(run.expectedTestIdentities,old.expectedTestIdentities)&&eq(run.actualTestIdentities,old.expectedTestIdentities),'ACTUAL_PRIOR_2004_SUITE_REQUIRED');
  const log=await b.read(run.log,run.logSha256),actual=execution(log,path.join(oldWarm,'apps/jentra_desktop'),old.expectedTestIdentities);
  must(actual.parsed?.allTestsPassed&&actual.parsed.passedTests===2004&&actual.parsed.failedTests===0&&actual.parsed.skippedTests===0,'ACTUAL_PRIOR_LOG_NOT_2004_GREEN');
  must(candidate.cases?.length===83&&new Set(candidate.cases.map(c=>c.test)).size===83&&candidate.bundleSha256==='0e0426bf2e302afcc00adb9602bfb3a6448b6ac558fb85cceaf18d62027832bd','ORIGINAL_APPROVED_83_CASES_REQUIRED');
  must(sha(Buffer.from(JSON.stringify(candidate.bundle)))===candidate.bundleSha256,'ORIGINAL_83_BUNDLE_HASH_INVALID');
  const owner=await b.json(priorOwnerPath),promotion=await b.json(priorPromotionPath);
  must(owner.kind==='direct-human-owner-decision'&&owner.submittedByOwner===true&&owner.images?.length===83&&owner.candidateBundleSha256===candidate.bundleSha256&&promotion.fullPromotion===true&&promotion.status==='complete'&&promotion.publishedImageCount===83&&promotion.candidateBundleSha256===candidate.bundleSha256,'ORIGINAL_83_DIRECT_APPROVAL_AND_PROMOTION_REQUIRED');
  must(Array.isArray(old.bindings)&&new Set(old.bindings.map(r=>r.path)).size===old.bindings.length,'PRIOR_BASE_BINDINGS_REQUIRED');
  for(const binding of old.bindings)await b.read(binding.path,binding.sha256);
  const priorR4Verification=await auditR4History();
  for(const binding of priorR4Verification.bindings)await b.read(binding.path,binding.sha256);
  const priorR4Source=await b.json(priorR4Verification.sourceManifest.path,priorR4Verification.sourceManifest.sha256);
  for(const binding of priorR4Source.bindings)await b.read(binding.path,binding.sha256);
  const current=selected(await sources(root)),warm=selected(await sources(oldWarm));
  must(mapEq(warm,old.sourceHashes),'HISTORICAL_APPROVED_WARM_TREE_DRIFT');
  const changed=[...new Set([...Object.keys(old.sourceHashes),...Object.keys(current)])].filter(p=>old.sourceHashes[p]!==current[p]).sort();
  must(Object.keys(current).length===1068&&eq(changed,declaredDartPaths),'ONLY_FIVE_DECLARED_EXISTING_DART_DELTAS_ALLOWED');
  must(current['pubspec.lock']===old.sourceHashes['pubspec.lock']&&Object.keys(old.sourceHashes).filter(p=>p.endsWith('.png')).every(p=>current[p]===old.sourceHashes[p]),'LOCK_OR_APPROVED_IMAGE_CHANGED');
  const changedTestText=(await bytes(root,'apps/jentra_desktop/test/jentra_app_test.dart')).toString('utf8');
  const explicitNames=new Set([...changedTestText.matchAll(/testWidgets\(\s*'([^']+)'/g)].map(m=>m[1]));
  for(const id of newTestIdentities){
    must(!old.expectedTestIdentities.includes(id),'NEW_TEST_ALREADY_IN_OLD_SUITE');
    const name=id.slice(id.indexOf(': ')+2);
    must(explicitNames.has(name),'EXPLICIT_NEW_TEST_DECLARATION_MISSING:'+name);
  }
  const goldens83=candidate.cases.map(c=>c.test).sort(),expected=[...old.expectedTestIdentities,...newTestIdentities].sort();
  must(declaredGoldenFailures.every(r=>goldens83.includes(r.testIdentity)&&typeof current[r.goldenPath]==='string'),'DECLARED_EIGHT_NOT_IN_APPROVED_83');
  const toolchain=await toolPins(old.toolchain),cached=await cachedInputs(oldWarm);
  for(const p of scriptPaths)await b.read(p);
  await b.finish();
  must(mapEq(selected(await sources(root)),current)&&mapEq(selected(await sources(oldWarm)),old.sourceHashes),'SOURCE_CHANGED_DURING_R5_INPUT_AUDIT');
  return{
    checkedAt:new Date().toISOString(),workspace:root,revision:'r5',selectedSources:1068,sourceInputCount:1068,
    sourceHashes:current,sourceInputs:current,sourceInputsSha256:sha(Buffer.from(JSON.stringify(current))),dependencyScope:scope,
    originalApprovedSource:{path:oldSourcePath,sha256:priorSourceSha},originalApprovedFullRun:{path:oldRunPath,sha256:priorRunSha},
    original83Approval:b.bound.get(priorOwnerPath),original83Promotion:b.bound.get(priorPromotionPath),
    priorR4Verification,
    declaredDartDelta:changed.map(p=>({path:p,approvedBaseSha256:old.sourceHashes[p],r5Sha256:current[p]})),
    newTestIdentities,originalExpectedTestIdentities:old.expectedTestIdentities,expectedTestIdentities:expected,goldens83TestIdentities:goldens83,
    declaredExpectedGoldenFailures:declaredGoldenFailures,stages:stageDefinitions(expected,goldens83),
    toolchain,sdkPins:toolchain.tooling,...cached,cachedInputOrigin:oldWarm,
    bindings:[...b.bound.values()],sourceStable:true,postImageApproval:false,approvedRepositoryImagesChanged:false,
    sharedSourceChanged:false,localStoresCopied:false,SDKExecuted:false,nativeLaunched:false,ownerAcceptanceChanged:false,boundary,
  };
}

async function copyTree(snapshot,manifest,origin){
  const relative=path.relative(root,snapshot);must(relative.startsWith('build'+path.sep)&&!relative.includes('..'),'EXACT_NEW_BUILD_TREE_REQUIRED');
  must(!await exists(relative),'NEW_SNAPSHOT_REQUIRED_PRESERVE_EXISTING:'+relative);
  const buildParent=path.dirname(snapshot);await mkdir(buildParent,{recursive:true});
  must(await realpath(buildParent)===buildParent&&!(await lstat(buildParent)).isSymbolicLink(),'BUILD_PARENT_LINK_REFUSED');
  await mkdir(snapshot);
  const copies=[...Object.entries(manifest.sourceHashes).map(([p,h])=>({p,h,parent:root})),
    ...[...manifest.resolution,...manifest.cachedSupport].map(r=>({p:r.path,h:r.sha256,parent:origin}))];
  for(const{p,h,parent}of copies){
    const target=inside(snapshot,p);await mkdir(path.dirname(target),{recursive:true});
    must(await realpath(path.dirname(target))===path.dirname(target),'COPY_PARENT_LINK_REFUSED:'+p);
    must(sha(await bytes(parent,p))===h,'COPY_SOURCE_CHANGED:'+p);
    await copyFile(inside(parent,p),target,constants.COPYFILE_EXCL);
    must(sha(await bytes(snapshot,p))===h,'COPY_HASH_MISMATCH:'+p);
  }
  must(mapEq(selected(await sources(snapshot)),manifest.sourceHashes),'COPIED_1068_SOURCE_MISMATCH');
}

async function recheck(manifest){
  must(mapEq(selected(await sources(root)),manifest.sourceHashes),'CURRENT_SOURCE_CHANGED_DURING_R5_FREEZE');
  for(const b of manifest.bindings)must(sha(await bytes(root,b.path))===b.sha256,'BOUND_INPUT_CHANGED_DURING_R5_FREEZE:'+b.path);
  must(eq(await toolPins(manifest.toolchain),manifest.toolchain),'SDK_CHANGED_DURING_R5_FREEZE');
}

async function approvalAudit(){
  const b=await binders(),priorRaw=await b.read(sourcePath),prior=parse(priorRaw);
  must(prior.kind==='desktop_verification_source_manifest'&&prior.revision==='r5'&&prior.postImageApproval===false,'PRIOR_R5_PREAPPROVAL_MANIFEST_REQUIRED');
  for(const binding of prior.bindings)await b.read(binding.path,binding.sha256);
  // Old r5 inputs remain in both isolated trees even after the eight root PNGs
  // have been promoted. Historical SDK logs are audited without pretending the
  // now changed root image map is still the preapproval source.
  const strict=await auditStage('goldens83',{checkCurrent:false}),generation=await auditStage('candidate8',{checkCurrent:false}),comparison=await auditStage('candidate8Strict',{checkCurrent:false});
  for(const a of [strict,generation,comparison]){await b.read(a.record.path,a.record.sha256);await b.read(a.log.path,a.log.sha256);await b.read(a.recordData.sdkExitRecord,a.recordData.sdkExitRecordSha256);}
  const generated=generation.recordData;
  must(eq(comparison.actualTestIdentities,declaredGoldenFailures.map(r=>r.testIdentity).sort())&&eq(comparison.recordData.candidateGeneration,generation.record),'ACTUAL_STRICT_CANDIDATE_EIGHT_REQUIRED');
  const owner=await b.json(ownerPath),promotion=await b.json(promotionPath);
  must(owner.kind==='direct-human-owner-decision'&&owner.authorizationKind==='direct-human-message'&&owner.submittedByOwner===true&&owner.sourceMessage?.role==='user'&&
    typeof owner.sourceMessage.messageId==='string'&&owner.sourceMessage.messageId.trim()&&typeof owner.sourceMessage.threadId==='string'&&owner.sourceMessage.threadId.trim()&&Number.isFinite(Date.parse(owner.sourceMessage.receivedAt)),'NEW_DIRECT_HUMAN_EXACT_EIGHT_DECISION_REQUIRED');
  must(typeof owner.messageVerbatim==='string'&&owner.messageVerbatim.trim()&&owner.messageSha256===sha(Buffer.from(owner.messageVerbatim))&&owner.candidateBundleSha256===generated.candidateBundleSha256&&owner.images?.length===8&&new Set(owner.images.map(r=>r.approvedPath)).size===8,'NEW_OWNER_SCOPE_OR_MESSAGE_INVALID');
  must(owner.packet?.path===base+'golden-owner-review-20261010-r5.json'&&typeof owner.reviewSha256==='string','EXACT_NEW_OWNER_REVIEW_REQUIRED');
  const packet=await b.json(owner.packet.path,owner.packet.sha256);
  must(sha(Buffer.from(JSON.stringify(packet.reviewCore)))===packet.reviewSha256&&packet.reviewSha256===owner.reviewSha256&&packet.reviewCore.candidateBundleSha256===generated.candidateBundleSha256,'EXACT_REVIEW_HASH_AND_CANDIDATE_REQUIRED');
  if(packet.html)await b.read(packet.html.path,packet.html.sha256);
  for(const ref of packet.reviewCore.refs??[])await b.read(ref.path,ref.sha256);
  must(promotion.status==='complete'&&promotion.fullPromotion===true&&promotion.failure===null&&promotion.cleanupErrors?.length===0&&promotion.postVerificationErrors?.length===0&&promotion.publishedImageCount===8&&promotion.candidateBundleSha256===generated.candidateBundleSha256&&promotion.ownerDecision?.path===ownerPath&&promotion.ownerDecision.sha256===b.bound.get(ownerPath).sha256&&promotion.remainingImages?.length===0&&promotion.claimedWithoutPublication?.length===0,'COMPLETE_NEW_EXACT_EIGHT_PROMOTION_REQUIRED');
  must(promotion.sourceEdits===0&&promotion.comparatorEdits===0&&promotion.fixturePermissionEdits===0&&promotion.ownerAcceptanceCriteriaChanged===0,'NEW_PROMOTION_SCOPE_CHANGED');
  must(promotion.changedImages?.length===8&&promotion.observedDestinations?.length===8&&promotion.retainedRecoveries?.length===8&&
    typeof promotion.recoveryDirectory==='string'&&new RegExp('^docs/verification/wave5/golden-promotion-recovery-20261010-r5-[0-9a-f-]+$').test(promotion.recoveryDirectory),'EXACT_EIGHT_PUBLICATION_AND_RECOVERY_OBSERVATIONS_REQUIRED');
  const decisions=new Map(owner.images.map(r=>[r.approvedPath,r])),changes=new Map(promotion.changedImages.map(r=>[r.path,r])),destinations=new Map(promotion.observedDestinations.map(r=>[r.path,r])),recoveries=new Map(promotion.retainedRecoveries.map(r=>[r.path,r]));
  must(changes.size===8&&destinations.size===8&&recoveries.size===8,'UNIQUE_EIGHT_PROMOTION_OBSERVATIONS_REQUIRED');
  const expected={...prior.sourceHashes},delta=[];
  for(const c of generated.cases){
    const decision=decisions.get(c.approvedPath),change=changes.get(c.approvedPath),observed=destinations.get(c.approvedPath);
    must(decision?.decision==='accept'&&decision.candidateSha256===c.candidateSha256&&change?.originalSha256===c.approvedSha256&&change.expectedCandidateSha256===c.candidateSha256&&change.currentSha256===c.candidateSha256&&change.matchesCandidate===true&&observed?.exists===true&&observed.currentSha256===c.candidateSha256&&observed.matchesCandidate===true&&!observed.error,'OWNER_PROMOTION_EIGHT_MISMATCH:'+c.stem);
    const recoveryPath=promotion.recoveryDirectory+'/'+path.basename(c.approvedPath),recovery=recoveries.get(recoveryPath);
    must(recovery?.sha256===c.approvedSha256&&recovery.claimedSha256===c.approvedSha256&&recovery.originalSha256===c.approvedSha256&&recovery.originalMatched===true&&recovery.published===true&&!recovery.error,'EXACT_EIGHT_RECOVERY_MISMATCH:'+c.stem);
    await b.read(recoveryPath,c.approvedSha256);await b.read(c.approvedBackup,c.approvedSha256);await b.read(c.candidatePath,c.candidateSha256);await b.read(c.diffPath,c.diffSha256);
    expected[c.approvedPath]=c.candidateSha256;delta.push({path:c.approvedPath,priorSha256:c.approvedSha256,approvedSha256:c.candidateSha256});
  }
  for(const binding of promotion.validatedBindings??[])await b.read(binding.path,binding.sha256);
  for(const binding of promotion.bindingsAfter?.bindings??[])await b.read(binding.path,binding.sha256);
  must(mapEq(selected(await sources(root)),expected)&&mapEq(selected(await sources(prior.snapshot)),prior.sourceHashes),'ONLY_EIGHT_APPROVED_ROOT_IMAGE_SUBSTITUTIONS_ALLOWED');
  const candidateInputs=selected(await sources(prior.candidateSnapshot));must(mapEq(candidateInputs,expected),'EXACT_APPROVED_CANDIDATE_TREE_REQUIRED');
  const cached=await cachedInputs(prior.snapshot);must(eq(cached.resolution,prior.resolution)&&eq(cached.cachedSupport,prior.cachedSupport),'R5_CACHED_SUPPORT_OR_RESOLUTION_CHANGED');
  const tooling=await toolPins(prior.toolchain);for(const p of scriptPaths)await b.read(p);
  await b.finish();
  const snapshot=path.join(root,'build/w5verification20261010/r5-approved');
  return{...prior,checkedAt:new Date().toISOString(),snapshot,executionWorkspace:snapshot,workingDirectory:path.join(snapshot,'apps/jentra_desktop'),
    sourceHashes:expected,sourceInputs:expected,sourceInputsSha256:sha(Buffer.from(JSON.stringify(expected))),toolchain:tooling,sdkPins:tooling.tooling,
    bindings:[...b.bound.values()],postImageApproval:true,approvedRepositoryImagesChanged:true,
    priorSourceManifest:{path:sourcePath,sha256:sha(priorRaw)},ownerImageDecision:b.bound.get(ownerPath),promotion:b.bound.get(promotionPath),
    ownerReview:b.bound.get(owner.packet.path),candidateGeneration:generation.record,candidateStrictRun:comparison.record,exactApprovedImageDelta:delta,
    SDKExecuted:false,fullSuitePassed:false,ownerAcceptanceChanged:false,boundary,
  };
}

async function main(){
  const mode=process.argv[2]??'check';must(process.argv.length<=3&&['check','freeze','approved-check','approved-freeze'].includes(mode),'R5_PREPARATION_MODE_INVALID');
  const approved=mode.startsWith('approved-'),audit=approved?await approvalAudit():await initialAudit();
  if(mode.endsWith('check')){
    console.log(JSON.stringify({mode,eligible:true,selectedSources:1068,declaredDartChanges:5,newBehaviorCases:6,fullExpectedTests:2010,expectedGoldenChanges:8,
      sourceInputsSha256:audit.sourceInputsSha256,stages:audit.stages.map(s=>({stage:s.stage,selectedTests:s.expectedTestIdentities.length,command:[s.executable,...s.args],workingDirectory:s.workingDirectory})),outputsWritten:false,SDKExecuted:false}));return;
  }
  const output=approved?approvedSourcePath:sourcePath,snapshot=path.join(root,'build/w5verification20261010',approved?'r5-approved':'r5'),candidateSnapshot=path.join(root,'build/w5verification20261010/r5-candidate');
  must(!await exists(output)&&!await exists(path.relative(root,snapshot))&&(approved||!await exists(path.relative(root,candidateSnapshot))),'R5_NEW_OUTPUTS_REQUIRED_PRESERVE_EXISTING');
  await recheck(audit);await copyTree(snapshot,audit,approved?path.join(root,'build/w5verification20261010/r5'):oldWarm);
  if(!approved)await copyTree(candidateSnapshot,audit,oldWarm);
  await recheck(audit);
  const manifest={kind:'desktop_verification_source_manifest',frozenAt:new Date().toISOString(),...audit,snapshot,executionWorkspace:snapshot,
    workingDirectory:path.join(snapshot,'apps/jentra_desktop'),candidateSnapshot};
  await writeFile(inside(root,output),JSON.stringify(manifest,null,2)+'\n',{flag:'wx'});
  await auditInputs(output);
  if(!approved)await auditInputs(output,{candidate:true});
  console.log(JSON.stringify({mode,manifest:output,sha256:sha(await bytes(root,output)),snapshot,selectedSources:1068,fullExpectedTests:2010,declaredDartChanges:5,approvedImageChanges:approved?8:0,SDKExecuted:false}));
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))await main();
