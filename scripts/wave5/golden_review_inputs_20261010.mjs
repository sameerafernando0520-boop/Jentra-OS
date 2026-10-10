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
  const manifestPath='docs/verification/wave5/golden-review-source-20261010-r1.json';
  const bytes=await readFile(path.join(root,manifestPath));
  const m=JSON.parse(bytes),expected={...m.sourceHashes};let overlays=[];let candidateManifest=null;
  if(path.resolve(m.snapshot)!==path.join(root,'build/w5goldens20261010/r1')||path.resolve(m.workspace)!==root)throw Error('EXECUTED_SNAPSHOT_BINDING_MISMATCH');
  if(['candidateAll','candidateGoldens','processDomain','platformAll','analyzer','build'].includes(stage)){
    const p='docs/verification/wave5/golden-review-candidate-20261010-r1.json';
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
