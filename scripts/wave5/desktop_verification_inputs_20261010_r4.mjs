// Read-only r4 input verification. No argument parser, SDK launch or publication.
import {lstat,readFile,realpath} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {sources} from './cash_ui_evidence.mjs';
import {executedTests,parseTestLog,verifierProvenance} from './accounting_execution_verifier_20261010_r3.mjs';

export const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
export const base='docs/verification/wave5/';
export const sourcePath=base+'desktop-verification-source-20261010-r4.json';
export const approvedSourcePath=base+'desktop-verification-source-20261010-r4-approved.json';
export const preparerPath='scripts/wave5/prepare_desktop_verification_20261010_r4.mjs';
export const helperPath='scripts/wave5/desktop_verification_inputs_20261010_r4.mjs';
export const runnerPath='scripts/wave5/run_desktop_verification_20261010_r4.mjs';
export const sdk='C:/src/flutter/bin/cache/dart-sdk/bin/dart.exe';
export const flutter='C:/src/flutter/bin/cache/flutter_tools.snapshot';
export const scope=['apps/jentra_desktop','packages/jentra_design_system','packages/jentra_domain','packages/jentra_platform'];
export const sha=b=>createHash('sha256').update(b).digest('hex');
export const eq=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
export const mapEq=(a,b)=>eq(Object.entries(a).sort(),Object.entries(b).sort());
export const must=(condition,message)=>{if(!condition)throw Error(message);};
export const parse=b=>JSON.parse(b.toString('utf8').replace(/^\uFEFF/,''));
export function inside(parent,relative){
  must(typeof relative==='string'&&relative&&!path.isAbsolute(relative),'RELATIVE_INPUT_REQUIRED');
  const absolute=path.resolve(parent,relative),rel=path.relative(parent,absolute);
  must(rel&&rel!=='..'&&!rel.startsWith('..'+path.sep)&&!path.isAbsolute(rel),'INPUT_ESCAPES:'+relative);
  return absolute;
}
export async function bytes(parent,relative){
  const file=inside(parent,relative),stat=await lstat(file),resolved=await realpath(file);
  must(stat.isFile()&&!stat.isSymbolicLink()&&resolved===file,'REGULAR_UNLINKED_INPUT_REQUIRED:'+relative);
  return readFile(file);
}
export async function exists(relative){try{await lstat(inside(root,relative));return true;}catch(e){if(e.code==='ENOENT')return false;throw e;}}
export const selected=hashes=>Object.fromEntries(Object.entries(hashes).filter(([p])=>
  ['pubspec.yaml','pubspec.lock','analysis_options.yaml'].includes(p)||scope.some(s=>p.startsWith(s+'/'))||/^apps\/[^/]+\/pubspec.yaml$/.test(p)));

// Diagnostic [E] echoes are excluded; actual test-start entries remain exact.
export function execution(raw,cwd,expected){
  const files=[...new Set(expected.map(id=>'test/'+id.slice(0,id.indexOf(': '))))].sort();
  const identities=executedTests(raw.toString('utf8'),cwd,files).filter(id=>!id.endsWith(' [E]')).map(id=>id.slice(5));
  must(identities.length===expected.length&&new Set(identities).size===identities.length&&eq(identities,[...expected].sort()),'EXACT_UNIQUE_SELECTED_IDENTITIES_REQUIRED');
  return{parsed:parseTestLog(raw.toString('utf8')),identities,actualFiles:files};
}

export async function auditInputs(manifestPath=sourcePath,{candidate=false,allowGeneratedImages=false}={}){
  must([sourcePath,approvedSourcePath].includes(manifestPath),'EXACT_R4_MANIFEST_PATH_REQUIRED');
  const raw=await bytes(root,manifestPath),manifest=parse(raw),bindings=[];
  must(manifest.kind==='desktop_verification_source_manifest'&&manifest.revision==='r4'&&manifest.selectedSources===1068&&
    manifest.sourceInputCount===1068&&Object.keys(manifest.sourceHashes).length===1068&&mapEq(manifest.sourceHashes,manifest.sourceInputs)&&
    manifest.sourceInputsSha256===sha(Buffer.from(JSON.stringify(manifest.sourceHashes)))&&eq(manifest.dependencyScope,scope),'EXACT_R4_SOURCE_SCOPE_REQUIRED');
  const expectedSnapshot=path.join(root,'build/w5verification20261010',manifestPath===sourcePath?'r4':'r4-approved');
  must(manifest.snapshot===expectedSnapshot&&manifest.executionWorkspace===expectedSnapshot&&manifest.workingDirectory===path.join(expectedSnapshot,'apps/jentra_desktop'),'EXACT_R4_EXECUTION_TREE_REQUIRED');
  const tree=candidate?manifest.candidateSnapshot:manifest.snapshot;
  must(!candidate||tree===path.join(root,'build/w5verification20261010/r4-candidate'),'EXACT_CANDIDATE_TREE_REQUIRED');
  const [current,copied]=await Promise.all([sources(root),sources(tree)]),currentSelected=selected(current),copiedSelected=selected(copied);
  must(mapEq(currentSelected,manifest.sourceHashes),'CURRENT_R4_INPUT_DRIFT');
  const actualDelta=[...new Set([...Object.keys(manifest.sourceHashes),...Object.keys(copiedSelected)])].filter(p=>manifest.sourceHashes[p]!==copiedSelected[p]).sort();
  const allowed=manifest.declaredExpectedGoldenFailures.map(r=>r.goldenPath).sort();
  must(actualDelta.length===0||(candidate&&allowGeneratedImages&&actualDelta.every(p=>allowed.includes(p))&&
    actualDelta.every(p=>typeof copiedSelected[p]==='string')),'EXECUTION_SOURCE_OR_UNDECLARED_IMAGE_DRIFT');
  for(const b of manifest.bindings){const actual=sha(await bytes(root,b.path));must(actual===b.sha256,'BOUND_R4_INPUT_DRIFT:'+b.path);bindings.push({...b});}
  for(const b of verifierProvenance)must(sha(await bytes(root,b.path))===b.sha256,'FROZEN_VERIFIER_PROVENANCE_DRIFT:'+b.path);
  const toolchain=[];
  must(eq(manifest.toolchain.tooling.map(t=>t.path),['C:/src/flutter/bin/cache/flutter.version.json',sdk,flutter,'C:/src/flutter/bin/cache/artifacts/engine/windows-x64/flutter_tester.exe'])&&eq(manifest.sdkPins,manifest.toolchain.tooling),'FOUR_EXACT_TOOL_PINS_REQUIRED');
  for(const t of manifest.toolchain.tooling){const actual=sha(await readFile(t.path));must(actual===t.sha256,'R4_SDK_TOOL_DRIFT:'+t.path);toolchain.push({...t});}
  must(eq(parse(await readFile(toolchain[0].path)),manifest.toolchain.sdkMetadata),'R4_SDK_METADATA_DRIFT');
  const resolution=[];
  for(const r of manifest.resolution){const actual=sha(await bytes(tree,r.path));must(actual===r.sha256,'R4_RESOLUTION_DRIFT:'+r.path);resolution.push({...r});}
  must(eq(resolution.map(r=>r.path),['.dart_tool/package_config.json','.dart_tool/package_graph.json','.dart_tool/version']),'EXACT_CACHED_RESOLUTION_REQUIRED');
  const config=parse(await bytes(tree,'.dart_tool/package_config.json'));
  must(config.configVersion===2&&Array.isArray(config.packages)&&new Set(config.packages.map(p=>p.name)).size===config.packages.length,'R4_PACKAGE_CONFIGURATION_INVALID');
  const configUrl=new URL('file:///'+tree.replaceAll('\\','/')+'/.dart_tool/package_config.json');
  for(const member of scope){
    const name=(await bytes(tree,member+'/pubspec.yaml')).toString('utf8').match(/^name:\s*([a-z0-9_]+)\s*$/m)?.[1];
    const pkg=config.packages.find(p=>p.name===name);
    must(pkg&&path.resolve(fileURLToPath(new URL(pkg.rootUri,configUrl)))===path.join(tree,member),'R4_WORKSPACE_DEPENDENCY_ESCAPES:'+member);
  }
  for(const b of bindings)must(sha(await bytes(root,b.path))===b.sha256,'INPUT_CHANGED_DURING_R4_AUDIT:'+b.path);
  return{checkedAt:new Date().toISOString(),sourceManifest:{path:manifestPath,sha256:sha(raw)},snapshot:tree,selectedSources:1068,
    currentSourceMatchesFrozenInputs:true,warmSourceMatchesFrozenInputs:actualDelta.length===0,candidateOnlyGeneratedImagesAllowed:candidate&&allowGeneratedImages,
    currentInputsSha256:sha(Buffer.from(JSON.stringify(currentSelected))),snapshotInputsSha256:sha(Buffer.from(JSON.stringify(copiedSelected))),
    sourceHashes:manifest.sourceHashes,snapshotSourceHashes:copiedSelected,generatedImageChanges:actualDelta.map(p=>({path:p,beforeSha256:manifest.sourceHashes[p],afterSha256:copiedSelected[p]})),
    toolchain:{sdkMetadata:manifest.toolchain.sdkMetadata,tooling:toolchain},resolution,bindings};
}
