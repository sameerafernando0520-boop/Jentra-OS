import {readFile,copyFile,rename,unlink,open,mkdir} from 'node:fs/promises';
import {constants} from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {sources} from './cash_ui_evidence.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const base='docs/verification/wave5/';
const sha=b=>createHash('sha256').update(b).digest('hex');
const read=async p=>readFile(path.join(root,p));
// Bind each file to the exact bytes used for validation. A later read cannot
// silently establish a new baseline after the first validation.
const boundHashes=new Map();
const readBound=async p=>{
  const bytes=await read(p),hash=sha(bytes);
  if(boundHashes.has(p)&&boundHashes.get(p)!==hash)throw Error('INPUT_CHANGED_DURING_VALIDATION:'+p);
  boundHashes.set(p,hash);return bytes;
};
const json=async p=>JSON.parse((await readBound(p)).toString('utf8'));
const selected=(p,m)=>['pubspec.yaml','pubspec.lock','analysis_options.yaml'].includes(p)||
  m.dependencyScope.some(s=>p.startsWith(s+'/'))||/^apps\/[^/]+\/pubspec.yaml$/.test(p);
async function checkSource(m,expected,ignored=new Set()){
  const current=await sources(root);
  const actual=Object.fromEntries(Object.entries(current).filter(([p])=>selected(p,m)&&!ignored.has(p)));
  if(JSON.stringify(actual)!==JSON.stringify(expected)){
    const changed=[...new Set([...Object.keys(actual),...Object.keys(expected)])].filter(p=>actual[p]!==expected[p]);
    throw Error('CURRENT_SOURCE_DRIFT:'+changed.join(','));
  }
  return{checkedAt:new Date().toISOString(),selectedSources:Object.keys(actual).length,sha256:sha(Buffer.from(JSON.stringify(actual)))};
}
async function checkBindings(){
  for(const[p,h]of boundHashes)if(sha(await read(p))!==h)throw Error('REVIEW_INPUT_DRIFT:'+p);
  return{checkedAt:new Date().toISOString(),bindings:[...boundHashes].map(([path,sha256])=>({path,sha256}))};
}
// Claim the actual existing bytes atomically into an owned recovery directory.
// A concurrent destination appearing afterward makes exclusive copy fail; it is never
// overwritten. Claimed files stay retained even when publication fails.
async function claimAndPublishImage(state){
  await rename(state.target,state.recovery);
  state.claimed=true;
  state.recoverySha256=sha(await readFile(state.recovery));
  if(state.recoverySha256!==state.originalSha256)throw Error('CONCURRENT_APPROVED_IMAGE_CHANGE:'+state.stem);
  await copyFile(state.temp,state.target,constants.COPYFILE_EXCL);
  state.published=true;
}
async function observeDestinations(states){
  const observed=[];
  for(const state of states){
    let currentSha256=null,error=null,exists=true;
    try{currentSha256=sha(await readFile(state.target));}
    catch(e){exists=e.code!=='ENOENT';error=e.code==='ENOENT'?null:e.message;}
    observed.push({path:state.path,currentSha256,exists,error,
      matchesOriginal:currentSha256===state.originalSha256,matchesCandidate:currentSha256===state.candidateSha256});
  }
  return observed;
}
async function observeRecoveries(states){
  const observed=[];
  for(const state of states.filter(s=>s.claimed)){
    let sha256=null,error=null;
    try{sha256=sha(await readFile(state.recovery));}catch(e){error=e.message;}
    observed.push({path:state.recoveryPath,sha256,error,claimedSha256:state.recoverySha256,
      originalSha256:state.originalSha256,originalMatched:sha256===state.originalSha256,published:state.published});
  }
  return observed;
}
const mode=process.argv[2]??'check';
if(!['check','apply'].includes(mode))throw Error('MODE_INVALID');
const candidatePath=base+'golden-review-candidate-20261010-r1.json';
const c=await json(candidatePath);
const m=await json(c.sourceManifest.path);
if(sha(await readBound(c.sourceManifest.path))!==c.sourceManifest.sha256||sha(Buffer.from(JSON.stringify(c.bundle)))!==c.bundleSha256)throw Error('CANDIDATE_MANIFEST_DRIFT');
const projection=c.cases.map(r=>({stem:r.stem,approvedPath:r.approvedPath,approvedSha256:r.approvedSha256,candidateSha256:r.candidateSha256}));
if(JSON.stringify(projection)!==JSON.stringify(c.bundle.cases)||JSON.stringify(c.sourceManifest)!==JSON.stringify(c.bundle.sourceManifest)||JSON.stringify(c.control)!==JSON.stringify(c.bundle.control))throw Error('CANDIDATE_PROJECTION_DRIFT');
if(sha(await readBound(c.control.path))!==c.control.sha256)throw Error('CONTROL_RECORD_DRIFT');
const run=await json(base+'golden-review-candidateGoldens-20261010-r1.json');
if(run.exitCode!==0||run.counts?.passed!==83||run.counts.failed!==0||run.counts.skipped!==0||run.integrityError||!run.inputAuditAfter?.snapshotMatchesDeclaredInputs)throw Error('STRICT_CANDIDATE_NOT_GREEN');
if(sha(await readBound(run.log))!==run.logSha256)throw Error('CANDIDATE_LOG_DRIFT');
if(run.inputAuditBefore?.candidateManifest?.sha256!==sha(await readBound(candidatePath))||run.inputAuditAfter.candidateManifest.sha256!==sha(await readBound(candidatePath))||
  run.inputAuditAfter.candidateManifest.bundleSha256!==c.bundleSha256||run.inputAuditAfter.sourceManifest.sha256!==c.sourceManifest.sha256||
  JSON.stringify(run.expectedCaseIdentities)!==JSON.stringify(c.cases.map(r=>r.test).sort()))throw Error('CANDIDATE_EXECUTION_BINDING_DRIFT');
await checkSource(m,m.sourceHashes);
if(c.cases.length!==83||new Set(c.cases.map(r=>r.approvedPath)).size!==83||new Set(c.cases.map(r=>r.stem)).size!==83)throw Error('EXACT83_REQUIRED');
const images=[];
for(const row of c.cases){
  if(!/^apps\/jentra_desktop\/test\/goldens\/[a-zA-Z0-9_-]+\.png$/.test(row.approvedPath))throw Error('TARGET_OUTSIDE_GOLDENS');
  const image=await read(row.candidatePath),approved=await read(row.approvedPath),backup=await read(row.approvedBackup);
  if(sha(image)!==row.candidateSha256||sha(approved)!==row.approvedSha256||sha(backup)!==row.approvedSha256)throw Error('IMAGE_DRIFT:'+row.stem);
  images.push({row,image});
}
if(mode==='check'){
  console.log(JSON.stringify({eligibleForExactOwnerDecision:true,cases:83,bundleSha256:c.bundleSha256,approvedImagesChanged:false,ownerDecisionRequired:true}));
}else{
  // The calling agent must have direct human authorization; this file is its
  // audit record, never a browser draft or a substitute for asking the owner.
  const ownerPath=process.argv[3];
  if(!ownerPath||!/^docs\/verification\/wave5\/owner-golden-decision-[a-zA-Z0-9_-]+\.json$/.test(ownerPath))throw Error('DIRECT_OWNER_RECORD_REQUIRED');
  const ownerBytes=await readBound(ownerPath),owner=JSON.parse(ownerBytes),ownerHash=sha(ownerBytes);
  const packet=await json(base+'golden-owner-review-20261010-r1.json');
  if(sha(Buffer.from(JSON.stringify(packet.reviewCore)))!==packet.reviewSha256||packet.reviewCore.candidateBundleSha256!==c.bundleSha256||
    JSON.stringify(packet.reviewCore.images)!==JSON.stringify(c.cases)||packet.reviewCore.run.sha256!==sha(await readBound(base+'golden-review-candidateGoldens-20261010-r1.json'))||
    sha(await readBound(packet.html.path))!==packet.html.sha256)throw Error('OWNER_PACKET_BINDING_DRIFT');
  for(const ref of packet.reviewCore.refs??[])if(sha(await readBound(ref.path))!==ref.sha256)throw Error('OWNER_PACKET_REFERENCE_DRIFT:'+ref.path);
  if(owner.kind!=='direct-human-owner-decision'||owner.authorizationKind!=='direct-human-message'||!owner.messageVerbatim?.trim()||
    owner.candidateBundleSha256!==c.bundleSha256||owner.reviewSha256!==packet.reviewSha256||owner.images?.length!==83)throw Error('OWNER_AUTHORIZATION_INVALID');
  const decisions=new Map(owner.images.map(r=>[r.approvedPath,r]));
  if(decisions.size!==83||images.some(({row})=>decisions.get(row.approvedPath)?.decision!=='accept'||decisions.get(row.approvedPath)?.candidateSha256!==row.candidateSha256))throw Error('EXACT83_OWNER_APPROVAL_REQUIRED');
  const recoveryDirectory=base+'golden-promotion-recovery-20261010-r1-'+randomUUID();
  const states=images.map(({row})=>({stem:row.stem,path:row.approvedPath,target:path.join(root,row.approvedPath),
    originalSha256:row.approvedSha256,candidateSha256:row.candidateSha256,
    recoveryPath:recoveryDirectory+'/'+path.basename(row.approvedPath),
    recovery:path.join(root,recoveryDirectory,path.basename(row.approvedPath)),
    temp:null,tempOwned:false,claimed:false,published:false,recoverySha256:null}));
  const startedAt=new Date().toISOString();let failure=null,sourceAfter=null,bindingsAfter=null,observed=[],recoveries=[];const cleanupErrors=[],postVerificationErrors=[];
  const result=await open(path.join(root,base+'golden-promotion-result-20261010-r1.json'),'wx');
  try{
    await mkdir(path.join(root,recoveryDirectory));
    await result.writeFile(JSON.stringify({status:'in_progress',startedAt,ownerDecision:{path:ownerPath,sha256:ownerHash},candidateBundleSha256:c.bundleSha256,
      recoveryDirectory,plannedImages:states.map(s=>({path:s.path,originalSha256:s.originalSha256,candidateSha256:s.candidateSha256,recoveryPath:s.recoveryPath})),
      boundary:'An interrupted attempt requires observed destination/recovery reconciliation; this initial journal is not a zero-change claim.'},null,2)+'\n');
    for(let i=0;i<images.length;i++){
      states[i].temp=path.join(root,images[i].row.approvedPath+'.'+randomUUID()+'.tmp');
      const temp=await open(states[i].temp,'wx');states[i].tempOwned=true;
      try{await temp.writeFile(images[i].image);}finally{await temp.close();}
    }
    const ownedTemps=new Set(states.filter(s=>s.tempOwned).map(s=>path.relative(root,s.temp).split(path.sep).join('/')));
    await checkSource(m,m.sourceHashes,ownedTemps);
    await checkBindings();
    for(const state of states)await claimAndPublishImage(state);
  }catch(e){failure=e.message;}finally{
    for(const{temp,tempOwned}of states)if(tempOwned)try{await unlink(temp);}catch(e){if(e.code!=='ENOENT')cleanupErrors.push({path:temp,error:e.message});}
    if(cleanupErrors.length&&!failure)failure='PROMOTION_TEMP_CLEANUP_FAILED';
    observed=await observeDestinations(states);
    recoveries=await observeRecoveries(states);
    const afterExpected={...m.sourceHashes};for(const state of states)afterExpected[state.path]=state.candidateSha256;
    try{sourceAfter=await checkSource(m,afterExpected);}catch(e){postVerificationErrors.push({gate:'sourceAfter',error:e.message});if(!failure)failure=e.message;}
    try{bindingsAfter=await checkBindings();}catch(e){postVerificationErrors.push({gate:'bindingsAfter',error:e.message});if(!failure)failure=e.message;}
    if(!failure&&observed.some(s=>!s.matchesCandidate||s.error))failure='DESTINATION_HASH_DRIFT_AFTER_PROMOTION';
    if(!failure&&recoveries.some(s=>s.error||s.sha256!==s.claimedSha256||!s.originalMatched))failure='RECOVERY_HASH_DRIFT_AFTER_PROMOTION';
    const changed=states.filter(s=>s.published);
    const observations=new Map(observed.map(s=>[s.path,s]));
    const report={startedAt,finishedAt:new Date().toISOString(),ownerDecision:{path:ownerPath,sha256:ownerHash},candidateBundleSha256:c.bundleSha256,
      status:failure?'failed':'complete',failure,cleanupErrors,postVerificationErrors,recoveryDirectory,
      changedImages:changed.map(s=>({path:s.path,originalSha256:s.originalSha256,expectedCandidateSha256:s.candidateSha256,
        currentSha256:observations.get(s.path).currentSha256,matchesCandidate:observations.get(s.path).matchesCandidate})),
      retainedRecoveries:recoveries,
      claimedWithoutPublication:states.filter(s=>s.claimed&&!s.published).map(s=>({path:s.path,recoveryPath:s.recoveryPath,recoverySha256:s.recoverySha256,
        observedDestination:observations.get(s.path)})),
      remainingImages:states.filter(s=>!s.published).map(s=>s.path),observedDestinations:observed,
      sourceAfter,bindingsAfter,validatedBindings:[...boundHashes].map(([path,sha256])=>({path,sha256})),
      fullPromotion:!failure&&changed.length===83&&observed.every(s=>s.matchesCandidate)&&!!sourceAfter&&!!bindingsAfter,
      publishedImageCount:changed.length,sourceEdits:0,comparatorEdits:0,fixturePermissionEdits:0,ownerAcceptanceCriteriaChanged:0,
      boundary:'Exact owner-approved visual baselines only. A fresh approved-image suite must still pass. No Wave5 criterion, genuine/native/runtime/production/billing acceptance is inferred.'};
    report.ownerDecision.sha256=ownerHash;
    try{await result.truncate(0);await result.write(JSON.stringify(report,null,2)+'\n',0,'utf8');}finally{await result.close();}
  }
  if(failure)throw Error('PARTIAL_PROMOTION_REQUIRES_NEW_REVIEWED_ATTEMPT:'+failure);
  console.log(JSON.stringify({promoted:states.filter(s=>s.published).length,criteriaAccepted:0,requiresFreshVerification:true,recoveryDirectory}));
}
