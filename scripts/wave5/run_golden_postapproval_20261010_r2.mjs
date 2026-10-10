// Preserve the r2 review, then verify the full desktop suite after exact promotion.
// Default check is read-only. freeze writes a new immutable source record only.
// run launches the serialized SDK job; the calling root must authorize that job.
import {lstat,open,readFile,realpath,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {sources} from './cash_ui_evidence.mjs';
import {parseTestLog} from './record_continuation_windows.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const base='docs/verification/wave5/';
const mode=process.argv[2]??'check';
if(process.argv.length>3||!['check','freeze','run'].includes(mode))throw Error('MODE_INVALID');
const paths={source:base+'golden-review-source-20261010-r2.json',candidate:base+'golden-review-candidate-20261010-r2.json',
  packet:base+'golden-owner-review-20261010-r2.json',control:base+'golden-review-controlAll-20261010-r2.json',
  candidateRun:base+'golden-review-candidateGoldens-20261010-r2.json',promotion:base+'golden-promotion-result-20261010-r2.json',
  manifest:base+'golden-review-postapproval-source-20261010-r2.json',log:base+'golden-review-approvedAll-20261010-r2.log',
  result:base+'golden-review-approvedAll-20261010-r2.json'};
const runnerPath='scripts/wave5/run_golden_postapproval_20261010_r2.mjs';
const sdk='C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe';
const flutter='C:/src/flutter/bin/cache/flutter_tools.snapshot';
const sha=b=>createHash('sha256').update(b).digest('hex');
const eq=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const must=(condition,message)=>{if(!condition)throw Error(message);};
function inside(p){
  must(typeof p==='string'&&!path.isAbsolute(p),'RELATIVE_INPUT_REQUIRED');
  const absolute=path.resolve(root,p),rel=path.relative(root,absolute);
  must(rel&&rel!=='..'&&!rel.startsWith('..'+path.sep)&&!path.isAbsolute(rel),'BOUND_INPUT_ESCAPES:'+p);
  return absolute;
}
async function bytes(p){
  const absolute=inside(p),stat=await lstat(absolute),resolved=await realpath(absolute),rel=path.relative(root,resolved);
  must(stat.isFile()&&!stat.isSymbolicLink()&&rel&&rel!=='..'&&!rel.startsWith('..'+path.sep)&&!path.isAbsolute(rel),'BOUND_INPUT_NOT_REGULAR:'+p);
  return readFile(absolute);
}
function testIdentities(text,workingDirectory,priorControl=false){
  const prefix=path.join(workingDirectory,'test').split(path.sep).join('/')+'/';
  const entries=[...text.replace(/\r/g,'').matchAll(/^\d+:\d+\s+\+\d+(?:\s+[~-]\d+)*:\s+(.+\.dart): (.+)$/gm)];
  return entries.filter(m=>m[2]!=='(setUpAll)'&&m[2]!=='(tearDownAll)'&&(!priorControl||!m[2].endsWith('[E]'))).map(m=>{
    const file=m[1].replaceAll('\\','/');must(file.startsWith(prefix),'TEST_EXECUTED_OUTSIDE_DESKTOP:'+file);
    const relative=file.slice(prefix.length);must(/^[A-Za-z0-9_/-]+\.dart$/.test(relative),'TEST_PATH_INVALID');
    return relative+': '+m[2];
  }).sort();
}
async function auditPostapproval(){
  const bound=new Map();
  const read=async(p,h)=>{const b=await bytes(p),actual=sha(b);must((!h||h===actual)&&(!bound.has(p)||bound.get(p)===actual),'BOUND_INPUT_DRIFT:'+p);bound.set(p,actual);return b;};
  const json=async(p,h)=>JSON.parse((await read(p,h)).toString('utf8').replace(/^\uFEFF/,''));
  const m=await json(paths.source),c=await json(paths.candidate),packet=await json(paths.packet),control=await json(paths.control),run=await json(paths.candidateRun),promotion=await json(paths.promotion);
  const snapshot=path.join(root,'build/w5goldens20261010/r1'),cwd=path.join(snapshot,'apps/jentra_desktop');
  must(path.resolve(m.workspace)===root&&path.resolve(m.snapshot)===snapshot&&m.sourceStable===true&&m.selectedSourceCount===1068&&Object.keys(m.sourceHashes).length===1068,'PRIOR1068_SCOPE_INVALID');
  must(c.cases.length===83&&new Set(c.cases.map(r=>r.approvedPath)).size===83&&new Set(c.cases.map(r=>r.stem)).size===83,'EXACT83_IMAGES_REQUIRED');
  must(eq(c.sourceManifest,c.bundle.sourceManifest)&&eq(c.control,c.bundle.control)&&c.sourceManifest.path===paths.source&&c.sourceManifest.sha256===bound.get(paths.source)&&c.control.path===paths.control&&c.control.sha256===bound.get(paths.control)&&sha(Buffer.from(JSON.stringify(c.bundle)))===c.bundleSha256,'CANDIDATE_BINDING_INVALID');
  must(eq(c.cases.map(({stem,approvedPath,approvedSha256,candidateSha256})=>({stem,approvedPath,approvedSha256,candidateSha256})),c.bundle.cases),'CANDIDATE_PROJECTION_INVALID');
  for(const flag of ['comparatorChanged','fixturePermissionsChanged','approvedRepositoryImagesChanged','ownerAccepted'])must(c[flag]===false,'HISTORICAL_CANDIDATE_BOUNDARY_CHANGED:'+flag);
  must(sha(Buffer.from(JSON.stringify(packet.reviewCore)))===packet.reviewSha256&&packet.reviewCore.candidateBundleSha256===c.bundleSha256&&eq(packet.reviewCore.images,c.cases)&&packet.reviewCore.run.path===paths.candidateRun&&packet.reviewCore.run.sha256===bound.get(paths.candidateRun),'PACKET_BINDING_INVALID');
  await read(packet.html.path,packet.html.sha256);
  for(const ref of packet.reviewCore.refs??[])await read(ref.path,ref.sha256);
  must(promotion.status==='complete'&&promotion.fullPromotion===true&&promotion.failure===null&&promotion.cleanupErrors?.length===0&&promotion.postVerificationErrors?.length===0&&promotion.publishedImageCount===83&&promotion.candidateBundleSha256===c.bundleSha256&&promotion.remainingImages?.length===0&&promotion.claimedWithoutPublication?.length===0,'FULL_PROMOTION_REQUIRED');
  must(promotion.sourceEdits===0&&promotion.comparatorEdits===0&&promotion.fixturePermissionEdits===0&&promotion.ownerAcceptanceCriteriaChanged===0,'PROMOTION_SCOPE_INVALID');
  const ownerPath=promotion.ownerDecision?.path;
  must(typeof ownerPath==='string'&&/^docs\/verification\/wave5\/owner-golden-decision-[A-Za-z0-9_-]+\.json$/.test(ownerPath),'OWNER_RECORD_PATH_INVALID');
  const owner=await json(ownerPath,promotion.ownerDecision.sha256);
  must(owner.kind==='direct-human-owner-decision'&&owner.authorizationKind==='direct-human-message'&&owner.submittedByOwner===true&&owner.sourceMessage?.role==='user'&&typeof owner.sourceMessage.messageId==='string'&&owner.sourceMessage.messageId.trim()&&typeof owner.sourceMessage.threadId==='string'&&owner.sourceMessage.threadId.trim()&&Number.isFinite(Date.parse(owner.sourceMessage.receivedAt)),'DIRECT_OWNER_RECORD_REQUIRED');
  must(typeof owner.messageVerbatim==='string'&&owner.messageVerbatim.trim()&&owner.messageSha256===sha(Buffer.from(owner.messageVerbatim))&&owner.reviewSha256===packet.reviewSha256&&owner.candidateBundleSha256===c.bundleSha256&&owner.images?.length===83,'OWNER_SCOPE_OR_MESSAGE_INVALID');
  const decisions=new Map(owner.images.map(r=>[r.approvedPath,r]));must(decisions.size===83,'OWNER_DECISIONS_NOT_UNIQUE');
  const expected={...m.sourceHashes},delta=[];
  must(promotion.changedImages?.length===83&&promotion.observedDestinations?.length===83&&promotion.retainedRecoveries?.length===83,'EXACT83_PROMOTION_OBSERVATIONS_REQUIRED');
  const changes=new Map(promotion.changedImages.map(r=>[r.path,r])),observed=new Map(promotion.observedDestinations.map(r=>[r.path,r]));
  must(changes.size===83&&observed.size===83,'PROMOTION_OBSERVATIONS_NOT_UNIQUE');
  must(typeof promotion.recoveryDirectory==='string'&&/^docs\/verification\/wave5\/golden-promotion-recovery-20261010-r2-[0-9a-f-]+$/.test(promotion.recoveryDirectory),'RECOVERY_DIRECTORY_INVALID');
  const recoveryMap=new Map(promotion.retainedRecoveries.map(r=>[r.path,r]));must(recoveryMap.size===83,'RECOVERIES_NOT_UNIQUE');
  for(const r of c.cases){
    must(/^apps\/jentra_desktop\/test\/goldens\/[A-Za-z0-9_-]+\.png$/.test(r.approvedPath)&&expected[r.approvedPath]===r.approvedSha256&&r.candidateSha256!==r.approvedSha256,'APPROVED_SUBSTITUTION_INVALID');
    const decision=decisions.get(r.approvedPath),change=changes.get(r.approvedPath),actual=observed.get(r.approvedPath);
    must(decision?.decision==='accept'&&decision.candidateSha256===r.candidateSha256&&change?.originalSha256===r.approvedSha256&&change.expectedCandidateSha256===r.candidateSha256&&change.currentSha256===r.candidateSha256&&change.matchesCandidate===true&&actual?.currentSha256===r.candidateSha256&&actual.matchesCandidate===true&&actual.exists===true&&!actual.error,'EXACT_OWNER_PROMOTION_MISMATCH:'+r.stem);
    const recoveryPath=promotion.recoveryDirectory+'/'+path.basename(r.approvedPath),recovery=recoveryMap.get(recoveryPath);
    must(recovery?.sha256===r.approvedSha256&&recovery.claimedSha256===r.approvedSha256&&recovery.originalSha256===r.approvedSha256&&recovery.originalMatched===true&&recovery.published===true&&!recovery.error,'RECOVERY_RECORD_MISMATCH:'+r.stem);
    await read(recoveryPath,r.approvedSha256);await read(r.approvedBackup,r.approvedSha256);await read(r.candidatePath,r.candidateSha256);
    expected[r.approvedPath]=r.candidateSha256;delta.push({path:r.approvedPath,priorSha256:r.approvedSha256,approvedSha256:r.candidateSha256});
  }
  for(const binding of promotion.validatedBindings??[])await read(binding.path,binding.sha256);
  must(promotion.sourceAfter?.selectedSources===1068&&promotion.sourceAfter.sha256===sha(Buffer.from(JSON.stringify(expected)))&&Array.isArray(promotion.bindingsAfter?.bindings),'PROMOTION_FINAL_SOURCE_PROOF_INVALID');
  for(const binding of promotion.bindingsAfter.bindings)await read(binding.path,binding.sha256);
  const controlLog=(await read(control.log,control.logSha256)).toString('utf8'),parsedControl=parseTestLog(controlLog);
  must(control.stage==='controlAll'&&control.exitCode===1&&control.integrityError===null&&eq(control.counts,{passed:1921,failed:83,skipped:0})&&parsedControl?.passedTests===1921&&parsedControl.failedTests===83&&parsedControl.skippedTests===0&&parsedControl.failures.length===83&&parsedControl.failures.every(r=>r.kind==='golden-comparison'),'RETAINED_FULL_CONTROL_REQUIRED');
  const expectedIdentities=testIdentities(controlLog,cwd,true);
  must(expectedIdentities.length===2004&&new Set(expectedIdentities).size===2004,'EXACT2004_RETAINED_IDENTITIES_REQUIRED');
  const runLog=(await read(run.log,run.logSha256)).toString('utf8'),parsedRun=parseTestLog(runLog);
  must(run.stage==='candidateGoldens'&&run.exitCode===0&&run.integrityError===null&&eq(run.counts,{passed:83,failed:0,skipped:0})&&parsedRun?.allTestsPassed&&parsedRun.passedTests===83&&parsedRun.failedTests===0&&parsedRun.skippedTests===0&&eq(testIdentities(runLog,cwd),c.cases.map(r=>r.test).sort()),'STRICT83_EXECUTION_REQUIRED');
  const controlFailurePairs=parsedControl.failures.map(r=>{
    const n=r.name.replaceAll('\\','/');return n.slice(n.indexOf('/test/')+6)+'|'+r.golden;
  }).sort();
  must(eq(controlFailurePairs,c.cases.map(r=>r.test+'|goldens/'+r.stem+'.png').sort()),'EXACT83_RETAINED_CONTROL_FAILURES_REQUIRED');
  const baseHash=sha(Buffer.from(JSON.stringify(m.sourceHashes))),approvedHash=sha(Buffer.from(JSON.stringify(expected)));
  const overlays=c.cases.map(r=>({path:r.approvedPath,baseSha256:r.approvedSha256,candidateSha256:r.candidateSha256}));
  for(const s of [control,run]){
    must(s.workingDirectory===cwd&&Date.parse(s.startedAt)>=Date.parse(m.capturedAt)&&Date.parse(s.startedAt)<=Date.parse(s.finishedAt),'RETAINED_STAGE_TIME_OR_SCOPE_INVALID');
    for(const a of [s.inputAuditBefore,s.inputAuditAfter])must(a?.selectedSources===1068&&a.snapshotMatchesDeclaredInputs===true&&a.currentWorkspaceMatchesFrozenBase===true&&eq(a.sourceManifest,c.sourceManifest)&&a.currentInputsSha256===baseHash&&a.snapshotInputsSha256===(s===control?baseHash:approvedHash)&&eq(a.overlays,s===control?[]:overlays)&&eq(a.candidateManifest,s===control?null:{path:paths.candidate,sha256:bound.get(paths.candidate),bundleSha256:c.bundleSha256}),'RETAINED_STAGE_INPUT_BINDING_INVALID');
    const {checkedAt:beforeTime,...beforeAudit}=s.inputAuditBefore,{checkedAt:afterTime,...afterAudit}=s.inputAuditAfter;
    must(eq(beforeAudit,afterAudit),'RETAINED_STAGE_INPUT_DRIFT');
  }
  for(const s of [control,run])for(const b of [s.runner,s.inputAuditor])await read(b.path,b.sha256);
  const tooling=[];
  must(eq(control.inputAuditAfter.toolchain.tooling.map(r=>r.path),['C:/src/flutter/bin/cache/flutter.version.json',sdk,flutter,'C:/src/flutter/bin/cache/artifacts/engine/windows-x64/flutter_tester.exe']),'EXACT_DEFAULT_TOOLCHAIN_REQUIRED');
  for(const tool of control.inputAuditAfter.toolchain.tooling){const b=await readFile(tool.path),hash=sha(b);must(hash===tool.sha256,'PINNED_TOOL_DRIFT:'+tool.path);tooling.push({path:tool.path,sha256:hash});}
  const sdkMetadata=JSON.parse(await readFile('C:/src/flutter/bin/cache/flutter.version.json'));
  must(sdkMetadata.frameworkVersion==='3.47.5'&&sdkMetadata.dartSdkVersion==='3.13.4'&&eq(sdkMetadata,control.inputAuditAfter.toolchain.sdkMetadata)&&eq(run.inputAuditAfter.toolchain,control.inputAuditAfter.toolchain),'PINNED_TOOLCHAIN_DRIFT');
  for(const p of [runnerPath,'scripts/wave5/cash_ui_evidence.mjs','scripts/wave5/record_continuation_windows.mjs'])await read(p);
  const select=h=>Object.fromEntries(Object.entries(h).filter(([p])=>['pubspec.yaml','pubspec.lock','analysis_options.yaml'].includes(p)||m.dependencyScope.some(s=>p.startsWith(s+'/'))||/^apps\/[^/]+\/pubspec.yaml$/.test(p)));
  const [current,warm]=await Promise.all([sources(root),sources(snapshot)]),currentSelected=select(current),warmSelected=select(warm);
  must(eq(currentSelected,expected)&&eq(warmSelected,expected),'POSTAPPROVAL1068_SOURCE_DRIFT');
  const actualDelta=[...new Set([...Object.keys(currentSelected),...Object.keys(m.sourceHashes)])].filter(p=>currentSelected[p]!==m.sourceHashes[p]).sort();
  must(eq(actualDelta,delta.map(r=>r.path).sort()),'ONLY83_APPROVED_IMAGE_CHANGES_PERMITTED');
  for(const[p,h]of bound)must(sha(await bytes(p))===h,'INPUT_DRIFT_DURING_POSTAPPROVAL_AUDIT:'+p);
  return{checkedAt:new Date().toISOString(),snapshot,workingDirectory:cwd,sourceHashes:expected,selectedSources:1068,
    sourceInputsSha256:sha(Buffer.from(JSON.stringify(expected))),priorSourceManifest:{path:paths.source,sha256:bound.get(paths.source)},
    candidate:{path:paths.candidate,sha256:bound.get(paths.candidate),bundleSha256:c.bundleSha256},packet:{path:paths.packet,sha256:bound.get(paths.packet),reviewSha256:packet.reviewSha256},
    promotion:{path:paths.promotion,sha256:bound.get(paths.promotion)},ownerDecision:{path:ownerPath,sha256:bound.get(ownerPath)},
    exactApprovedImageDelta:delta,expectedTestIdentities:expectedIdentities,toolchain:{sdkMetadata,tooling},
    bindings:[...bound].map(([path,sha256])=>({path,sha256})),currentSourceMatchesApprovedInputs:true,warmSourceMatchesApprovedInputs:true,
    boundary:'Exact83 owner-approved PNG substitutions and their retained original bytes only. This audit does not itself execute tests or establish native/runtime/delivery/load/whole-system acceptance.'};
}
const initial=await auditPostapproval();
if(mode==='check'){
  console.log(JSON.stringify({mode,eligibleForFreshFullSuite:true,selectedSources:1068,approvedImageChanges:83,expectedTests:2004,sourceInputsSha256:initial.sourceInputsSha256,outputsWritten:false,sdkExecuted:false}));
}else if(mode==='freeze'){
  await writeFile(inside(paths.manifest),JSON.stringify({frozenAt:new Date().toISOString(),kind:'postapproval_desktop1068_source_manifest',...initial},null,2)+'\n',{flag:'wx'});
  console.log(JSON.stringify({mode,manifest:paths.manifest,sha256:sha(await bytes(paths.manifest)),selectedSources:1068,expectedTests:2004,sdkExecuted:false}));
}else{
  const manifestBytes=await bytes(paths.manifest),manifest=JSON.parse(manifestBytes);
  const stableKeys=['snapshot','workingDirectory','sourceHashes','selectedSources','sourceInputsSha256','priorSourceManifest','candidate','packet','promotion','ownerDecision','exactApprovedImageDelta','expectedTestIdentities','toolchain','bindings'];
  for(const k of stableKeys)must(eq(manifest[k],initial[k]),'FROZEN_POSTAPPROVAL_MANIFEST_DRIFT:'+k);
  const manifestHash=sha(manifestBytes),startedAt=new Date().toISOString();
  const args=[flutter,'--suppress-analytics','test','--no-pub','--concurrency=1','--reporter=expanded'];
  const result=await open(inside(paths.result),'wx');
  let log=null,exitCode=null,spawnError=null,integrityError=null,after=null,raw=Buffer.alloc(0),parsed=null,actualIdentities=[];
  await result.writeFile(JSON.stringify({status:'in_progress',stage:'approvedAll',startedAt,sourceManifest:{path:paths.manifest,sha256:manifestHash},executable:sdk,args,
    boundary:'Reserved before full-suite execution. An interrupted job has no passing-test claim.'},null,2)+'\n');
  try{
    log=await open(inside(paths.log),'wx');
    const env={...process.env};for(const n of ['W5_CASH_FRAME_DIR','W5_MODEL_FRAME_DIR','W5_AUTH_FRAME_DIR'])delete env[n];
    const child=spawn(sdk,args,{cwd:initial.workingDirectory,env,windowsHide:true,stdio:['ignore','pipe','pipe']});
    let chain=Promise.resolve();for(const stream of [child.stdout,child.stderr])stream.on('data',b=>{chain=chain.then(()=>log.write(b));});
    exitCode=await new Promise(resolve=>{child.on('error',e=>{spawnError={message:e.message,code:e.code??null};resolve(127);});child.on('exit',c=>resolve(c??1));});
    await chain;await log.close();log=null;raw=await bytes(paths.log);parsed=parseTestLog(raw.toString('utf8'));
    after=await auditPostapproval();
    must(sha(await bytes(paths.manifest))===manifestHash,'POSTAPPROVAL_MANIFEST_CHANGED_DURING_RUN');
    for(const k of stableKeys)must(eq(initial[k],after[k]),'POSTAPPROVAL_INPUT_CHANGED_DURING_RUN:'+k);
    actualIdentities=testIdentities(raw.toString('utf8'),initial.workingDirectory);
    must(exitCode===0&&parsed?.allTestsPassed&&parsed.passedTests===2004&&parsed.failedTests===0&&parsed.skippedTests===0,'FULL2004_SUITE_NOT_GREEN');
    must(actualIdentities.length===2004&&new Set(actualIdentities).size===2004&&eq(actualIdentities,initial.expectedTestIdentities),'EXACT2004_EXECUTIONS_REQUIRED');
  }catch(e){integrityError=e.message;}
  if(log)try{await log.close();}catch(e){integrityError??=e.message;}
  if(!raw.length)try{raw=await bytes(paths.log);parsed=parseTestLog(raw.toString('utf8'));}catch{}
  const fullSuitePassed=exitCode===0&&!integrityError&&!!after&&actualIdentities.length===2004;
  const report={stage:'approvedAll',status:fullSuitePassed?'complete':'failed',startedAt,finishedAt:new Date().toISOString(),workingDirectory:initial.workingDirectory,executable:sdk,args,
    sourceManifest:{path:paths.manifest,sha256:manifestHash},log:paths.log,logSha256:sha(raw),logBytes:raw.length,exitCode,spawnError,integrityError,
    counts:parsed?{passed:parsed.passedTests,failed:parsed.failedTests,skipped:parsed.skippedTests}:null,expectedTestIdentities:initial.expectedTestIdentities,actualTestIdentities:actualIdentities,
    inputAuditBefore:initial,inputAuditAfter:after,fullSuitePassed,ownerImageDecision:initial.ownerDecision,promotion:initial.promotion,
    approvedImageChanges:83,sourceEdits:0,comparatorEdits:0,fixturePermissionEdits:0,
    boundary:'Full strict desktop approved-image suite only, on the frozen1068 inputs after exact83 promotion. No native keyboard/MFA, actual delivery/model use, contention/load, runtime installation, whole-system owner signoff, production or billing is inferred.'};
  try{await result.truncate(0);await result.write(JSON.stringify(report,null,2)+'\n',0,'utf8');}finally{await result.close();}
  console.log(JSON.stringify({stage:report.stage,status:report.status,counts:report.counts,exitCode,integrityError,fullSuitePassed,sourceStable:!!after,log:paths.log}));
  if(!fullSuitePassed)process.exitCode=1;
}
