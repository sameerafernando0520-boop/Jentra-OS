import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {sources} from './cash_ui_evidence.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const sha=b=>createHash('sha256').update(b).digest('hex');
const members=['apps/jentra_desktop','packages/jentra_domain','packages/jentra_platform','packages/jentra_design_system'];
const select=hashes=>Object.fromEntries(Object.entries(hashes).filter(([p])=>
  ['pubspec.yaml','pubspec.lock','analysis_options.yaml'].includes(p)||members.some(m=>p.startsWith(m+'/'))||/^apps\/[^/]+\/pubspec.yaml$/.test(p)));
export async function auditGoldenInputs(stage){
  const manifestPath='docs/verification/wave5/golden-review-source-20261010-r2.json';
  const bytes=await readFile(path.join(root,manifestPath));
  const m=JSON.parse(bytes),expected={...m.sourceHashes};let overlays=[];let candidateManifest=null;
  if(path.resolve(m.snapshot)!==path.join(root,'build/w5goldens20261010/r1')||path.resolve(m.workspace)!==root)throw Error('EXECUTED_SNAPSHOT_BINDING_MISMATCH');
  const helpers=[
    {path:'apps/jentra_desktop/test/crm_workspace_test.dart',r1Sha256:'34bf4e259c7b3c879d8731a0dca166598e3514f9aa93f915b245b54dde6979d4',currentSha256:'bbcc4ae3c0f0a450b5b89db0562d984aa793ee8184e090764245d2e76a45475d'},
    {path:'apps/jentra_desktop/test/jentra_app_test.dart',r1Sha256:'02e5f75574367bba70ee0e24800b0e5cfa1fa3d5e5438811a075a8935a560e91',currentSha256:'fb1654528ae63934e70da80d5de1220c7f5eded3ddc175f1fef612960a79e336'},
  ];
  if(m.sourceReviewRevision!=='r2'||m.executionTreeRevision!=='r1'||m.sourceStable!==true||m.selectedSourceCount!==1068||Object.keys(expected).length!==1068||
    JSON.stringify(m.deltaFromR1)!==JSON.stringify(helpers)||helpers.some(h=>expected[h.path]!==h.currentSha256)||m.warmReuse?.changedWarmFiles?.length!==85||
    new Set(m.warmReuse.changedWarmFiles).size!==85)throw Error('GUARDED_R2_REUSE_PROOF_REQUIRED');
  for(const binding of [m.script,m.warmReuse.before,m.warmReuse.after,m.warmReuse.priorSourceManifest,m.warmReuse.priorCandidateManifest,m.warmReuse.coldFailureProof,
    ...m.warmReuse.originalHelperBackups]){
    const resolved=path.resolve(root,binding.path),relative=path.relative(root,resolved);
    if(path.isAbsolute(binding.path)||!relative||relative==='..'||relative.startsWith('..'+path.sep)||path.isAbsolute(relative)||sha(await readFile(resolved))!==binding.sha256)throw Error('R2_REUSE_BOUND_ARTIFACT_DRIFT');
  }
  const reuseAfter=JSON.parse(await readFile(path.join(root,m.warmReuse.after.path)));
  if(reuseAfter.warmTreeComplete!==true||reuseAfter.mutationError!==null||reuseAfter.sourceManifestOutput!==manifestPath||
    JSON.stringify(reuseAfter.changedWarmFiles)!==JSON.stringify(m.warmReuse.changedWarmFiles)||reuseAfter.remainingWarmFiles.length!==0)throw Error('R2_REUSE_PARTIAL_OR_FAILED');
  if(['candidateAll','candidateGoldens','processDomain','platformAll','analyzer','build'].includes(stage)){
    const p='docs/verification/wave5/golden-review-candidate-20261010-r2.json';
    const b=await readFile(path.join(root,p)),c=JSON.parse(b);
    if(c.sourceManifest.sha256!==sha(bytes)||sha(Buffer.from(JSON.stringify(c.bundle)))!==c.bundleSha256)throw Error('CANDIDATE_BINDING_DRIFT');
    const projection=c.cases.map(r=>({stem:r.stem,approvedPath:r.approvedPath,approvedSha256:r.approvedSha256,candidateSha256:r.candidateSha256}));
    if(JSON.stringify(projection)!==JSON.stringify(c.bundle.cases)||JSON.stringify(c.sourceManifest)!==JSON.stringify(c.bundle.sourceManifest)||JSON.stringify(c.control)!==JSON.stringify(c.bundle.control)||
      c.sourceManifest.path!==manifestPath||path.resolve(c.snapshot)!==path.resolve(m.snapshot))throw Error('CANDIDATE_DECLARATION_BINDING_MISMATCH');
    candidateManifest={path:p,sha256:sha(b),bundleSha256:c.bundleSha256};
    if(c.cases.length!==83||new Set(c.cases.map(r=>r.approvedPath)).size!==83)throw Error('EXACT83_OVERLAYS_REQUIRED');
    for(const r of c.cases){
      if(expected[r.approvedPath]!==r.approvedSha256)throw Error('BASELINE_OVERLAY_BASE_DRIFT');
      expected[r.approvedPath]=r.candidateSha256;overlays.push({path:r.approvedPath,baseSha256:r.approvedSha256,candidateSha256:r.candidateSha256});
    }
  }
  const copied=select(await sources(m.snapshot));
  if(JSON.stringify(copied)!==JSON.stringify(expected)){
    const changed=[...new Set([...Object.keys(copied),...Object.keys(expected)])].filter(p=>copied[p]!==expected[p]);
    throw Error('FROZEN_SOURCE_DRIFT:'+changed.join(','));
  }
  const current=select(await sources(root));
  if(JSON.stringify(current)!==JSON.stringify(m.sourceHashes))throw Error('CONCURRENT_CURRENT_SOURCE_DRIFT');
  const sdkMetadataPath='C:/src/flutter/bin/cache/flutter.version.json';
  const sdkBytes=await readFile(sdkMetadataPath),sdkMetadata=JSON.parse(sdkBytes);
  if(sdkMetadata.frameworkVersion!=='3.47.5'||sdkMetadata.dartSdkVersion!=='3.13.4')throw Error('PINNED_TOOLCHAIN_CHANGED');
  const tooling=[];
  for(const p of [sdkMetadataPath,'C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe','C:/src/flutter/bin/cache/flutter_tools.snapshot','C:/src/flutter/bin/cache/artifacts/engine/windows-x64/flutter_tester.exe']){
    tooling.push({path:p,sha256:sha(await readFile(p))});
  }
  return{checkedAt:new Date().toISOString(),sourceManifest:{path:manifestPath,sha256:sha(bytes)},
    selectedSources:Object.keys(expected).length,snapshotInputsSha256:sha(Buffer.from(JSON.stringify(copied))),
    currentInputsSha256:sha(Buffer.from(JSON.stringify(current))),candidateManifest,overlays,toolchain:{sdkMetadata,tooling},
    snapshotMatchesDeclaredInputs:true,currentWorkspaceMatchesFrozenBase:true};
}
