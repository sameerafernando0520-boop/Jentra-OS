import {copyFile, lstat, mkdir, readFile, readdir, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {sources} from './cash_ui_evidence.mjs';
import {parseTestLog} from './record_continuation_windows.mjs';
import {auditGoldenInputs} from './golden_review_inputs_20261010_r2.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const base='docs/verification/wave5/';
const snapshot=path.join(root,'build/w5goldens20261010/r1');
const manifest=base+'golden-review-source-20261010-r2.json';
const members=['apps/jentra_desktop','packages/jentra_domain','packages/jentra_platform','packages/jentra_design_system'];
const select=hashes=>Object.fromEntries(Object.entries(hashes).filter(([p])=>
  ['pubspec.yaml','pubspec.lock','analysis_options.yaml'].includes(p)||members.some(m=>p.startsWith(m+'/'))||/^apps\/[^/]+\/pubspec.yaml$/.test(p)));
const sha=b=>createHash('sha256').update(b).digest('hex');
const exists=async p=>{try{await lstat(p);return true;}catch(e){if(e.code==='ENOENT')return false;throw e;}};
const json=async p=>JSON.parse(await readFile(path.join(root,p),'utf8'));
const write=async(p,v)=>writeFile(path.join(root,p),JSON.stringify(v,null,2)+'\n',{flag:'wx'});
const mode=process.argv[2]??'snapshot';
if(mode==='snapshot'){
  // Reuse the already initialized tree. This mode never removes caches or copies
  // any state, dependency output or source outside the exact 85 declared files.
  const scriptPath='scripts/wave5/prepare_golden_review_20261010_r2.mjs';
  const beforePath=base+'golden-review-warm-reuse-before-20261010-r2.json';
  const afterPath=base+'golden-review-warm-reuse-after-20261010-r2.json';
  for(const p of [manifest,beforePath,afterPath])if(await exists(path.join(root,p)))throw Error('R2_IMMUTABLE_RECORD_ALREADY_EXISTS:'+p);
  if(!await exists(snapshot)||(await lstat(snapshot)).isSymbolicLink())throw Error('R1_WARM_TREE_REQUIRED');
  const eq=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
  const bindings=new Map();
  const inside=(directory,p)=>{
    if(typeof p!=='string'||path.isAbsolute(p))throw Error('RELATIVE_BOUND_PATH_REQUIRED');
    const resolved=path.resolve(directory,p),rel=path.relative(directory,resolved);
    if(!rel||rel==='..'||rel.startsWith('..'+path.sep)||path.isAbsolute(rel))throw Error('BOUND_PATH_ESCAPES:'+p);
    return resolved;
  };
  const bind=async(p,h)=>{
    const target=inside(root,p);
    if((await lstat(target)).isSymbolicLink())throw Error('BOUND_LINK_REFUSED:'+p);
    const b=await readFile(target),actual=sha(b);
    if((h&&h!==actual)||(bindings.has(p)&&bindings.get(p).sha256!==actual))throw Error('R1_BOUND_INPUT_DRIFT:'+p);
    bindings.set(p,{path:p,sha256:actual});return b;
  };
  const load=async p=>JSON.parse(await bind(p));
  const r1ManifestPath=base+'golden-review-source-20261010-r1.json';
  const r1CandidatePath=base+'golden-review-candidate-20261010-r1.json';
  const r1StagePath=base+'golden-review-candidateGoldens-20261010-r1.json';
  const coldProofPath=base+'golden-review-cold-asset-proof-20261010-r1.json';
  const r1=await load(r1ManifestPath),candidate=await load(r1CandidatePath),stage=await load(r1StagePath);
  const comparison=await load(base+'continuation-goldens-comparison-20261009-r13.json');
  const cold=await load(coldProofPath);
  await bind(scriptPath);
  if(path.resolve(r1.workspace)!==root||path.resolve(r1.snapshot)!==snapshot||r1.selectedSourceCount!==1068||Object.keys(r1.sourceHashes??{}).length!==1068||r1.sourceStable!==true)throw Error('R1_SOURCE_SCOPE_CHANGED');
  if(!eq(candidate.sourceManifest,candidate.bundle?.sourceManifest)||!eq(candidate.control,candidate.bundle?.control)||
    candidate.sourceManifest.path!==r1ManifestPath||candidate.sourceManifest.sha256!==bindings.get(r1ManifestPath).sha256||
    sha(Buffer.from(JSON.stringify(candidate.bundle)))!==candidate.bundleSha256||path.resolve(candidate.snapshot)!==snapshot||
    candidate.comparatorChanged!==false||candidate.fixturePermissionsChanged!==false||candidate.approvedRepositoryImagesChanged!==false||candidate.ownerAccepted!==false)throw Error('R1_CANDIDATE_BINDING_CHANGED');
  await bind(candidate.control.path,candidate.control.sha256);
  const projection=candidate.cases.map(({stem,approvedPath,approvedSha256,candidateSha256})=>({stem,approvedPath,approvedSha256,candidateSha256}));
  if(!eq(projection,candidate.bundle.cases)||candidate.cases.length!==83||new Set(candidate.cases.map(c=>c.stem)).size!==83||new Set(candidate.cases.map(c=>c.approvedPath)).size!==83)throw Error('R1_EXACT83_OVERLAYS_REQUIRED');
  const known=comparison.cases.map(c=>({stem:c.stem,approvedPath:c.approved,approvedSha256:c.approvedSha256}));
  if(!eq(projection.map(({candidateSha256,...c})=>c),known))throw Error('R1_APPROVED_IMAGE_PROJECTION_CHANGED');
  const authorized=[
    {path:'apps/jentra_desktop/test/crm_workspace_test.dart',r1Sha256:'34bf4e259c7b3c879d8731a0dca166598e3514f9aa93f915b245b54dde6979d4',currentSha256:'bbcc4ae3c0f0a450b5b89db0562d984aa793ee8184e090764245d2e76a45475d'},
    {path:'apps/jentra_desktop/test/jentra_app_test.dart',r1Sha256:'02e5f75574367bba70ee0e24800b0e5cfa1fa3d5e5438811a075a8935a560e91',currentSha256:'fb1654528ae63934e70da80d5de1220c7f5eded3ddc175f1fef612960a79e336'},
  ];
  const before=select(await sources(root)),expectedWarm={...r1.sourceHashes};
  const paths=[...new Set([...Object.keys(before),...Object.keys(r1.sourceHashes)])];
  const deltaFromR1=paths.filter(p=>before[p]!==r1.sourceHashes[p]).map(p=>({path:p,r1Sha256:r1.sourceHashes[p]??null,currentSha256:before[p]??null}));
  if(Object.keys(before).length!==1068||!eq(deltaFromR1,authorized))throw Error('ONLY_TWO_AUTHORIZED_HELPER_CHANGES_PERMITTED');
  const edits=[];
  for(const c of candidate.cases){
    if(!/^apps\/jentra_desktop\/test\/goldens\/[A-Za-z0-9_-]+\.png$/.test(c.approvedPath)||r1.sourceHashes[c.approvedPath]!==c.approvedSha256||before[c.approvedPath]!==c.approvedSha256||c.ownerAccepted!==false)throw Error('APPROVED_ROOT_IMAGE_DRIFT');
    await bind(c.candidatePath,c.candidateSha256);await bind(c.approvedBackup,c.approvedSha256);await bind(c.diffPath,c.diffSha256);
    expectedWarm[c.approvedPath]=c.candidateSha256;
    edits.push({path:c.approvedPath,beforeSha256:c.candidateSha256,afterSha256:c.approvedSha256,kind:'restore_original_approved_png',bytes:await readFile(inside(root,c.approvedPath))});
  }
  const copied=select(await sources(snapshot));
  if(!eq(copied,expectedWarm))throw Error('R1_WARM_SOURCE_OR83_OVERLAYS_CHANGED');
  const overlays=candidate.cases.map(c=>({path:c.approvedPath,baseSha256:c.approvedSha256,candidateSha256:c.candidateSha256}));
  for(const a of [stage.inputAuditBefore,stage.inputAuditAfter]){
    if(!a||a.selectedSources!==1068||a.snapshotMatchesDeclaredInputs!==true||a.currentWorkspaceMatchesFrozenBase!==true||
      a.sourceManifest?.path!==r1ManifestPath||a.sourceManifest.sha256!==bindings.get(r1ManifestPath).sha256||
      a.candidateManifest?.path!==r1CandidatePath||a.candidateManifest.sha256!==bindings.get(r1CandidatePath).sha256||a.candidateManifest.bundleSha256!==candidate.bundleSha256||
      a.currentInputsSha256!==sha(Buffer.from(JSON.stringify(r1.sourceHashes)))||a.snapshotInputsSha256!==sha(Buffer.from(JSON.stringify(expectedWarm)))||!eq(a.overlays,overlays))throw Error('R1_FINISHED_STAGE_SOURCE_BINDING_CHANGED');
  }
  const raw=await bind(stage.log,stage.logSha256),parsed=parseTestLog(raw.toString('utf8'));
  const expectedColdStems=['crm_1440_light_comfortable','dashboard_1440_light_comfortable','setup_1024_light_compact_text_200'];
  const normalize=n=>n.replaceAll('\\','/').slice(n.replaceAll('\\','/').indexOf('/test/')+6);
  const expectedColdNames=candidate.cases.filter(c=>expectedColdStems.includes(c.stem)).map(c=>c.test).sort();
  if(stage.stage!=='candidateGoldens'||stage.exitCode!==1||stage.integrityError!=='EXACT83_CANDIDATE_EXECUTIONS_NOT_GREEN'||!stage.finishedAt||
    Date.parse(stage.startedAt)>Date.parse(stage.finishedAt)||!eq(stage.counts,{passed:80,failed:3,skipped:0})||
    parsed?.passedTests!==80||parsed.failedTests!==3||parsed.skippedTests!==0||parsed.failures.some(f=>f.kind!=='golden-comparison')||
    !eq(parsed.failures.map(f=>normalize(f.name)).sort(),expectedColdNames))throw Error('EXPECTED_FINISHED_R1_COLD_LOGO_FAILURES_REQUIRED');
  for(const b of [stage.runner,stage.inputAuditor])await bind(b.path,b.sha256);
  if(!eq(cold.counts,stage.counts)||!eq(cold.stage,bindings.get(r1StagePath))||!eq(cold.log,bindings.get(stage.log))||
    !eq(cold.sourceManifest,bindings.get(r1ManifestPath))||!eq(cold.candidate,bindings.get(r1CandidatePath))||
    !eq(cold.cases.map(c=>c.stem).sort(),expectedColdStems))throw Error('COLD_FAILURE_PRESERVATION_BINDING_CHANGED');
  for(const c of cold.cases){
    if(c.artifacts.length!==3||new Set(c.artifacts.map(a=>a.kind)).size!==3)throw Error('EXACT_NINE_PRESERVED_DIAGNOSTICS_REQUIRED');
    for(const a of c.artifacts)await bind(a.preserved.path,a.preserved.sha256);
    await bind(c.sealedCandidate.path,c.sealedCandidate.sha256);
  }
  // Preserve the two original helper bodies before they are replaced in the copy.
  const originals=[];
  for(const a of authorized){
    if(r1.sourceHashes[a.path]!==a.r1Sha256||sha(await readFile(inside(snapshot,a.path)))!==a.r1Sha256)throw Error('R1_HELPER_HASH_CHANGED');
    const oldBytes=await readFile(inside(snapshot,a.path)),newBytes=await readFile(inside(root,a.path));
    if(sha(newBytes)!==a.currentSha256)throw Error('AUTHORIZED_HELPER_DRIFT');
    const p=base+'golden-review-original-helpers-20261010-r2/'+path.basename(a.path);
    if(await exists(inside(root,p)))throw Error('ORIGINAL_HELPER_BACKUP_EXISTS');
    originals.push({path:p,sha256:sha(oldBytes),bytes:oldBytes,originalPath:a.path});
    edits.unshift({path:a.path,beforeSha256:a.r1Sha256,afterSha256:a.currentSha256,kind:'await_brand_asset_decode_test_helper',bytes:newBytes});
  }
  const recheck=async(expectedCopy)=>{
    if(!eq(select(await sources(root)),before)||!eq(select(await sources(snapshot)),expectedCopy))throw Error('CONCURRENT_SOURCE_CHANGE_DURING_WARM_REUSE');
    for(const b of bindings.values())if(sha(await readFile(inside(root,b.path)))!==b.sha256)throw Error('CONCURRENT_R1_EVIDENCE_CHANGE:'+b.path);
  };
  await recheck(expectedWarm);
  for(const o of originals){await mkdir(path.dirname(inside(root,o.path)),{recursive:true});await writeFile(inside(root,o.path),o.bytes,{flag:'wx'});}
  const beforeRecord={capturedAt:new Date().toISOString(),kind:'guarded_r1_warm_tree_reuse_before',workspace:root,snapshot,
    priorSourceManifest:bindings.get(r1ManifestPath),priorCandidateManifest:bindings.get(r1CandidatePath),priorCandidateStage:bindings.get(r1StagePath),
    coldFailureProof:bindings.get(coldProofPath),sourceInputs:1068,priorCandidateOverlays:83,deltaFromR1,
    originalHelperBackups:originals.map(({bytes,...o})=>o),bindings:[...bindings.values()],
    currentInputsSha256:sha(Buffer.from(JSON.stringify(before))),warmInputsSha256:sha(Buffer.from(JSON.stringify(copied))),
    declaredWarmEdits:edits.map(({bytes,...e})=>e),ownerAccepted:false,approvedRepositoryImagesChanged:false,
    boundary:'Only two exact test helpers and 83 original approved PNGs may be copied into the existing warm execution tree. Frozen r1 review evidence and diagnostics remain unchanged. No cache deletion, SDK job, state copy or owner/live action.'};
  await write(beforePath,beforeRecord);
  const beforeBinding={path:beforePath,sha256:sha(await readFile(inside(root,beforePath)))};
  const changed=[];let mutationError=null;
  try{
    await recheck(expectedWarm);
    for(const e of edits){
      const target=inside(snapshot,e.path);
      if((await lstat(target)).isSymbolicLink()||sha(await readFile(target))!==e.beforeSha256||sha(await readFile(inside(root,e.path)))!==e.afterSha256)throw Error('EXACT_WARM_EDIT_PRECONDITION_CHANGED:'+e.path);
      await writeFile(target,e.bytes);
      if(sha(await readFile(target))!==e.afterSha256)throw Error('EXACT_WARM_EDIT_WRITE_FAILED:'+e.path);
      changed.push(e.path);
    }
    await recheck(before);
  }catch(e){mutationError={message:e.message,code:e.code??null};}
  const afterRecord={capturedAt:new Date().toISOString(),kind:'guarded_r1_warm_tree_reuse_result',before:beforeBinding,
    changedWarmFiles:changed,remainingWarmFiles:edits.map(e=>e.path).filter(p=>!changed.includes(p)),mutationError,
    warmTreeComplete:mutationError===null&&changed.length===85,sourceManifestOutput:manifest,
    ownerAccepted:false,approvedRepositoryImagesChanged:false,
    boundary:'A failed or partial reuse is recorded without rollback or cache deletion. The new manifest is issued only after all exact source and evidence postchecks pass.'};
  await write(afterPath,afterRecord);
  if(mutationError)throw Error('WARM_REUSE_FAILED:'+mutationError.message);
  await recheck(before);
  const r13=await json(base+'windows-test-preview-source-20261009-r13.json');
  const delta=Object.keys(before).filter(p=>r13.baseSourceHashes[p]!==before[p]).map(p=>({path:p,r13Sha256:r13.baseSourceHashes[p]??null,currentSha256:before[p]}));
  await write(manifest,{capturedAt:new Date().toISOString(),workspace:root,snapshot,sourceReviewRevision:'r2',executionTreeRevision:'r1',
    gitHead:execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim(),
    sourceHashes:before,selectedSourceCount:1068,deltaFromR13:delta,deltaFromR1,
    script:bindings.get(scriptPath),dependencyScope:members,sourceStable:true,overlays:[],storesCopied:false,sharedSourceChanged:false,
    warmReuse:{before:beforeBinding,after:{path:afterPath,sha256:sha(await readFile(inside(root,afterPath)))},
      priorSourceManifest:bindings.get(r1ManifestPath),priorCandidateManifest:bindings.get(r1CandidatePath),coldFailureProof:bindings.get(coldProofPath),
      originalHelperBackups:originals.map(({bytes,...o})=>o),changedWarmFiles:changed},
    boundary:'Frozen r2 desktop inputs in the guarded reused r1 warm tree. Only two authorized test-helper asset waits changed; all 83 approved PNGs restored in the copy. Root baselines, permissions, state and frozen r1 evidence remain unchanged. Fresh full approved control and candidate83 runs are required.'});
  console.log(JSON.stringify({snapshot,sourceReviewRevision:'r2',count:1068,deltaFromR1,restoredApprovedImages:83,sourceStable:true}));
}else if(mode==='candidate'){
  const m=await json(manifest),comparison=await json(base+'continuation-goldens-comparison-20261009-r13.json');
  const current=select(await sources(root));
  if(JSON.stringify(current)!==JSON.stringify(m.sourceHashes))throw Error('CURRENT_SOURCE_DRIFT');
  const copied=select(await sources(snapshot));
  if(JSON.stringify(copied)!==JSON.stringify(m.sourceHashes))throw Error('SNAPSHOT_SOURCE_DRIFT');
  const groupCounts={};for(const c of comparison.cases)groupCounts[c.classification]=(groupCounts[c.classification]??0)+1;
  if(comparison.cases.length!==83||new Set(comparison.cases.map(c=>c.stem)).size!==83||new Set(comparison.cases.map(c=>c.approved)).size!==83||
    groupCounts['localized-border-raster']!==65||groupCounts['capability-navigation-and-border-raster']!==16||groupCounts['payroll-content-change']!==2)throw Error('CASE_SET_CHANGED');
  const stage=await json(base+'golden-review-controlAll-20261010-r2.json');
  if(stage.stage!=='controlAll'||stage.exitCode!==1||stage.integrityError!==null||!stage.startedAt||!stage.finishedAt||
    Date.parse(stage.startedAt)<Date.parse(m.capturedAt)||Date.parse(stage.startedAt)>Date.parse(stage.finishedAt))throw Error('FRESH_R2_CONTROL_EXPECTED_83_FAILURES');
  const audit=await auditGoldenInputs('controlAll');
  for(const a of [stage.inputAuditBefore,stage.inputAuditAfter]){
    const stableKeys=['sourceManifest','candidateManifest','currentInputsSha256','snapshotInputsSha256','selectedSources','overlays','toolchain'];
    for(const k of stableKeys)if(JSON.stringify(a?.[k])!==JSON.stringify(audit[k]))throw Error('FRESH_R2_CONTROL_INPUT_BINDING_CHANGED:'+k);
    if(a.snapshotMatchesDeclaredInputs!==true||a.currentWorkspaceMatchesFrozenBase!==true)throw Error('FRESH_R2_CONTROL_SOURCE_NOT_GREEN');
  }
  for(const b of [stage.runner,stage.inputAuditor])if(sha(await readFile(path.join(root,b.path)))!==b.sha256)throw Error('FRESH_R2_CONTROL_TOOL_DRIFT');
  const log=await readFile(path.join(root,stage.log),'utf8');
  if(sha(Buffer.from(log))!==stage.logSha256)throw Error('CONTROL_LOG_DRIFT');
  const parsed=parseTestLog(log);
  if(parsed?.passedTests!==1921||parsed.failedTests!==83||parsed.skippedTests!==0||parsed.failures.length!==83)throw Error('CONTROL_COUNTS_CHANGED');
  const normalize=name=>name.slice(name.indexOf('/test/')+6);
  const expectedNames=comparison.cases.map(c=>normalize(c.name)).sort();
  const actualNames=parsed.failures.map(c=>normalize(c.name)).sort();
  if(JSON.stringify(expectedNames)!==JSON.stringify(actualNames)||parsed.failures.some(f=>f.kind!=='golden-comparison'))throw Error('CONTROL_FAILURE_SET_CHANGED');
  const expectedPairs=comparison.cases.map(c=>normalize(c.name)+'|'+c.golden).sort();
  const actualPairs=parsed.failures.map(c=>normalize(c.name)+'|'+c.golden).sort();
  if(JSON.stringify(expectedPairs)!==JSON.stringify(actualPairs))throw Error('CONTROL_GOLDEN_PAIRS_CHANGED');
  const failureFiles=await readdir(path.join(snapshot,'apps/jentra_desktop/test/failures'));
  const actualStems=failureFiles.filter(p=>p.endsWith('_testImage.png')).map(p=>p.slice(0,-14)).sort();
  if(JSON.stringify(actualStems)!==JSON.stringify(comparison.cases.map(c=>c.stem).sort()))throw Error('CONTROL_IMAGE_SET_CHANGED');
  const pngSize=b=>{if(b.readUInt32BE(0)!==0x89504e47||b.toString('ascii',12,16)!=='IHDR')throw Error('PNG_INVALID');return[b.readUInt32BE(16),b.readUInt32BE(20)];};
  const cases=[],evidenceBytes=[];
  for(const c of comparison.cases){
    const relative=c.approved;
    const currentPath=path.join(snapshot,'apps/jentra_desktop/test/failures',c.stem+'_testImage.png');
    const masterPath=path.join(snapshot,'apps/jentra_desktop/test/failures',c.stem+'_masterImage.png');
    const diffPath=path.join(snapshot,'apps/jentra_desktop/test/failures',c.stem+'_isolatedDiff.png');
    const image=await readFile(currentPath),master=await readFile(masterPath),diff=await readFile(diffPath);
    const dimensions=pngSize(image);
    if(JSON.stringify(dimensions)!==JSON.stringify(pngSize(master))||JSON.stringify(dimensions)!==JSON.stringify(pngSize(diff)))throw Error('FRESH_RENDER_DIMENSION_CHANGE');
    if(sha(await readFile(path.join(root,relative)))!==c.approvedSha256||sha(master)!==c.approvedSha256)throw Error('APPROVED_BASELINE_DRIFT');
    const original=await readFile(path.join(snapshot,relative));
    if(sha(original)!==c.approvedSha256)throw Error('SNAPSHOT_BASELINE_DRIFT');
    const old=c.renders.find(r=>r.kind==='testImage');
    const candidatePath=base+'golden-review-candidates-20261010-r2/'+c.stem+'.png';
    const approvedBackup=base+'golden-review-approved-20261010-r2/'+c.stem+'.png';
    const diffCopy=base+'golden-review-diffs-20261010-r2/'+c.stem+'.png';
    for(const[p,b]of[[candidatePath,image],[approvedBackup,original],[diffCopy,diff]]){
      if(await exists(path.join(root,p)))throw Error('CANDIDATE_EVIDENCE_ALREADY_EXISTS');
      evidenceBytes.push([p,b]);
    }
    cases.push({stem:c.stem,classification:c.classification,test:c.name.slice(c.name.indexOf('/test/')+6),approvedPath:relative,approvedSha256:c.approvedSha256,
      candidatePath,candidateSha256:sha(image),approvedBackup,diffPath:diffCopy,diffSha256:sha(diff),freshMatchesR13:sha(image)===old.r13Sha256,
      dimensions,strictOriginalComparisonPassed:false,ownerAccepted:false});
  }
  for(const[p,b]of evidenceBytes){await mkdir(path.dirname(path.join(root,p)),{recursive:true});await writeFile(path.join(root,p),b,{flag:'wx'});}
  // Baseline overlays apply only to this disposable copy, after all 83 prechecks.
  for(const c of cases)await copyFile(path.join(root,c.candidatePath),path.join(snapshot,c.approvedPath));
  const candidateManifest=base+'golden-review-candidate-20261010-r2.json';
  const sourceManifestSha=sha(await readFile(path.join(root,manifest)));
  const bundle={sourceManifest:{path:manifest,sha256:sourceManifestSha},control:{path:base+'golden-review-controlAll-20261010-r2.json',sha256:sha(await readFile(path.join(root,base+'golden-review-controlAll-20261010-r2.json')))},
    cases:cases.map(c=>({stem:c.stem,approvedPath:c.approvedPath,approvedSha256:c.approvedSha256,candidateSha256:c.candidateSha256}))};
  const bundleSha256=sha(Buffer.from(JSON.stringify(bundle)));
  await write(candidateManifest,{preparedAt:new Date().toISOString(),snapshot,sourceManifest:bundle.sourceManifest,control:bundle.control,bundleSha256,bundle,cases,
    counts:{cases:cases.length,freshMatchesR13:cases.filter(c=>c.freshMatchesR13).length},
    comparatorChanged:false,fixturePermissionsChanged:false,approvedRepositoryImagesChanged:false,ownerAccepted:false,
    boundary:'83 explicitly diagnosed image overlays in an isolated test copy only. A green candidate run cannot approve itself or satisfy native/runtime/owner gates.'});
  console.log(JSON.stringify({cases:cases.length,freshMatchesR13:cases.filter(c=>c.freshMatchesR13).length,bundleSha256,approvedRepositoryImagesChanged:false}));
}else throw Error('MODE_INVALID');
