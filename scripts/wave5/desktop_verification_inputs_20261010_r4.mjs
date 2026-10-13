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
export const oldSourcePath=base+'golden-review-postapproval-source-20261010-r2.json';
export const oldRunPath=base+'golden-review-approvedAll-20261010-r2.json';
export const oldCandidatePath=base+'golden-review-candidate-20261010-r2.json';
export const ownerPath=base+'owner-golden-decision-20261010-r4.json';
export const promotionPath=base+'golden-promotion-result-20261010-r4.json';
export const resolutionPaths=['.dart_tool/package_config.json','.dart_tool/package_graph.json','.dart_tool/version'];
export const supportPaths=['.dart_tool/pub/workspace_ref.json','apps/jentra_desktop/.flutter-plugins-dependencies','apps/jentra_desktop/.dart_tool/flutter_build/dart_plugin_registrant.dart'];
export const declaredDartPaths=[
  'apps/jentra_desktop/lib/src/features/setup/business_setup_screen.dart',
  'apps/jentra_desktop/lib/src/features/procurement/procurement_screen.dart',
  'apps/jentra_desktop/lib/src/features/shared/module_placeholder_screen.dart',
  'apps/jentra_desktop/test/jentra_app_test.dart',
  'apps/jentra_desktop/test/warehouse_setup_test.dart',
].sort();
export const newTestIdentities=[
  'development Preview setup explains memory-only examples',
  'configured setup without a gateway disables server confirmation',
  'configured setup gateway retains server confirmation presentation',
  'development Preview procurement explains unavailable accounting',
  'configured procurement subset explains missing connection',
  'Finance landing explains unavailable posting and reports',
].map(name=>'jentra_app_test.dart: '+name).sort();
const scenarios=['1024_light_compact','1024_dark_comfortable','1440_light_comfortable','1440_dark_compact','1920_light_comfortable','1920_dark_comfortable'];
export const declaredGoldenFailures=[
  ...scenarios.map(s=>({testIdentity:'jentra_app_test.dart: setup golden '+s+' — AC-216',goldenPath:'apps/jentra_desktop/test/goldens/setup_'+s+'.png'})),
  {testIdentity:'jentra_app_test.dart: Wave 2 setup remains reachable at 200% text scale — EC-224',goldenPath:'apps/jentra_desktop/test/goldens/setup_1024_light_compact_text_200.png'},
  {testIdentity:'warehouse_setup_test.dart: warehouse form uses selected branch and preserves scope on save',goldenPath:'apps/jentra_desktop/test/goldens/warehouse_setup_form.png'},
].sort((a,b)=>a.testIdentity.localeCompare(b.testIdentity));
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

export const stagePath=stage=>base+'desktop-verification-'+stage+'-20261010-r4.json';
export const stageLog=stage=>stagePath(stage).replace(/\.json$/,'.log');
export const stageExit=stage=>stagePath(stage).replace(/\.json$/,'.sdk-exit.json');
const escapeRegex=s=>s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
export function stageDefinitions(expectedTestIdentities,goldens83Identities){
  must(expectedTestIdentities.length===2010&&new Set(expectedTestIdentities).size===2010&&goldens83Identities.length===83&&new Set(goldens83Identities).size===83,'EXACT_2010_AND_83_IDENTITIES_REQUIRED');
  const affected=['jentra_app_test.dart','warehouse_setup_test.dart','command_palette_keyboard_test.dart','main_preview_startup_test.dart'];
  const goldenNames=new Set([...goldens83Identities,'jentra_app_test.dart: bundled typefaces render in the test engine']);
  const focused=expectedTestIdentities.filter(id=>affected.includes(id.slice(0,id.indexOf(': ')))&&!goldenNames.has(id)).sort();
  must(newTestIdentities.every(id=>focused.includes(id)),'SIX_NEW_BEHAVIOR_CASES_REQUIRED');
  const make=(stage,identities,{candidate=false,update=false,approved=false}={})=>{
    const tree=path.join(root,'build/w5verification20261010',candidate?'r4-candidate':approved?'r4-approved':'r4');
    const args=[flutter,'--suppress-analytics','test','--no-pub','--concurrency=1','--reporter=expanded'];
    if(update)args.push('--update-goldens');
    if(stage!=='approvedAll'){
      args.push('--name=^(?:'+[...new Set(identities.map(id=>id.slice(id.indexOf(': ')+2)))].map(escapeRegex).join('|')+')$');
      args.push(...[...new Set(identities.map(id=>'test/'+id.slice(0,id.indexOf(': '))))].sort());
    }
    return{stage,workingDirectory:path.join(tree,'apps/jentra_desktop'),executable:sdk,args,expectedTestIdentities:[...identities].sort(),candidateTree:candidate,goldenUpdate:update,postImageApproval:approved};
  };
  return[
    {stage:'analyzer',workingDirectory:path.join(root,'build/w5verification20261010/r4'),executable:sdk,
      args:['--suppress-analytics','analyze','apps/jentra_desktop/lib','apps/jentra_desktop/test','packages/jentra_domain','packages/jentra_platform','packages/jentra_design_system'],expectedTestIdentities:[],candidateTree:false,goldenUpdate:false,postImageApproval:false},
    make('focusedNonGolden',focused),make('goldens83',goldens83Identities),
    make('candidate8',declaredGoldenFailures.map(r=>r.testIdentity),{candidate:true,update:true}),
    make('candidate8Strict',declaredGoldenFailures.map(r=>r.testIdentity),{candidate:true}),
    make('approvedAll',expectedTestIdentities,{approved:true}),
  ];
}

// Diagnostic [E] echoes are excluded; actual test-start entries remain exact.
export function execution(raw,cwd,expected){
  const files=[...new Set(expected.map(id=>'test/'+id.slice(0,id.indexOf(': '))))].sort();
  const identities=executedTests(raw.toString('utf8'),cwd,files).filter(id=>!id.endsWith(' [E]')).map(id=>id.slice(5));
  must(identities.length===expected.length&&new Set(identities).size===identities.length&&eq(identities,[...expected].sort()),'EXACT_UNIQUE_SELECTED_IDENTITIES_REQUIRED');
  return{parsed:parseTestLog(raw.toString('utf8')),identities,actualFiles:files};
}

export function normalizedFailures(parsed,cwd){
  const prefix=cwd.replaceAll('\\','/').replace(/\/$/,'')+'/test/';
  return parsed.failures.map(f=>{
    const name=f.name.replaceAll('\\','/');
    must(name.startsWith(prefix)&&f.kind==='golden-comparison'&&/^goldens\/[^/]+\.png$/.test(f.golden??''),'ONLY_EXACT_DESKTOP_GOLDEN_FAILURES_ALLOWED');
    return{testIdentity:name.slice(prefix.length),goldenPath:'apps/jentra_desktop/test/'+f.golden};
  }).sort((a,b)=>a.testIdentity.localeCompare(b.testIdentity));
}

export async function auditInputs(manifestPath=sourcePath,{candidate=false,allowGeneratedImages=false}={}){
  must([sourcePath,approvedSourcePath].includes(manifestPath),'EXACT_R4_MANIFEST_PATH_REQUIRED');
  const raw=await bytes(root,manifestPath),manifest=parse(raw),bindings=[];
  must(manifest.kind==='desktop_verification_source_manifest'&&manifest.revision==='r4'&&manifest.selectedSources===1068&&
    manifest.sourceInputCount===1068&&Object.keys(manifest.sourceHashes).length===1068&&mapEq(manifest.sourceHashes,manifest.sourceInputs)&&
    manifest.sourceInputsSha256===sha(Buffer.from(JSON.stringify(manifest.sourceHashes)))&&eq(manifest.dependencyScope,scope),'EXACT_R4_SOURCE_SCOPE_REQUIRED');
  must(eq(manifest.declaredDartDelta.map(r=>r.path),declaredDartPaths)&&eq(manifest.declaredExpectedGoldenFailures,declaredGoldenFailures)&&
    eq(manifest.newTestIdentities,newTestIdentities)&&manifest.expectedTestIdentities.length===2010&&new Set(manifest.expectedTestIdentities).size===2010&&
    manifest.originalExpectedTestIdentities.length===2004&&new Set(manifest.originalExpectedTestIdentities).size===2004&&
    eq(manifest.expectedTestIdentities,[...manifest.originalExpectedTestIdentities,...newTestIdentities].sort()),'EXACT_DECLARED_FIVE_DART_AND_SIX_TEST_DELTAS_REQUIRED');
  must(eq(manifest.stages,stageDefinitions(manifest.expectedTestIdentities,manifest.goldens83TestIdentities)),'EXACT_R4_STAGE_DEFINITIONS_REQUIRED');
  must(manifest.postImageApproval===(manifestPath===approvedSourcePath)&&(!manifest.postImageApproval||manifest.exactApprovedImageDelta?.length===8&&manifest.ownerImageDecision?.path===ownerPath&&manifest.promotion?.path===promotionPath),'APPROVAL_MANIFEST_SCOPE_REQUIRED');
  const expectedSnapshot=path.join(root,'build/w5verification20261010',manifestPath===sourcePath?'r4':'r4-approved');
  must(manifest.snapshot===expectedSnapshot&&manifest.executionWorkspace===expectedSnapshot&&manifest.workingDirectory===path.join(expectedSnapshot,'apps/jentra_desktop'),'EXACT_R4_EXECUTION_TREE_REQUIRED');
  const tree=candidate?manifest.candidateSnapshot:manifest.snapshot;
  must(!candidate||tree===path.join(root,'build/w5verification20261010/r4-candidate'),'EXACT_CANDIDATE_TREE_REQUIRED');
  const [current,copied]=await Promise.all([sources(root),sources(tree)]),currentSelected=selected(current),copiedSelected=selected(copied);
  must(mapEq(currentSelected,manifest.sourceHashes),'CURRENT_R4_INPUT_DRIFT');
  const actualDelta=[...new Set([...Object.keys(manifest.sourceHashes),...Object.keys(copiedSelected)])].filter(p=>manifest.sourceHashes[p]!==copiedSelected[p]).sort();
  const allowed=declaredGoldenFailures.map(r=>r.goldenPath).sort();
  must(actualDelta.length===0||(candidate&&allowGeneratedImages&&actualDelta.every(p=>allowed.includes(p))&&
    actualDelta.every(p=>typeof copiedSelected[p]==='string')),'EXECUTION_SOURCE_OR_UNDECLARED_IMAGE_DRIFT');
  must(Array.isArray(manifest.bindings)&&manifest.bindings.length>0&&new Set(manifest.bindings.map(b=>b.path)).size===manifest.bindings.length,'UNIQUE_R4_BINDINGS_REQUIRED');
  for(const b of manifest.bindings){const actual=sha(await bytes(root,b.path));must(actual===b.sha256,'BOUND_R4_INPUT_DRIFT:'+b.path);bindings.push({...b});}
  for(const p of [helperPath,preparerPath,runnerPath,'scripts/wave5/cash_ui_evidence.mjs','scripts/wave5/accounting_execution_verifier_20261010_r3.mjs'])must(bindings.some(b=>b.path===p),'EXACT_VERIFICATION_SCRIPT_BINDING_REQUIRED:'+p);
  for(const b of verifierProvenance)must(sha(await bytes(root,b.path))===b.sha256,'FROZEN_VERIFIER_PROVENANCE_DRIFT:'+b.path);
  const toolchain=[];
  must(eq(manifest.toolchain.tooling.map(t=>t.path),['C:/src/flutter/bin/cache/flutter.version.json',sdk,flutter,'C:/src/flutter/bin/cache/artifacts/engine/windows-x64/flutter_tester.exe'])&&eq(manifest.sdkPins,manifest.toolchain.tooling),'FOUR_EXACT_TOOL_PINS_REQUIRED');
  for(const t of manifest.toolchain.tooling){const actual=sha(await readFile(t.path));must(actual===t.sha256,'R4_SDK_TOOL_DRIFT:'+t.path);toolchain.push({...t});}
  must(eq(parse(await readFile(toolchain[0].path)),manifest.toolchain.sdkMetadata),'R4_SDK_METADATA_DRIFT');
  const resolution=[];
  for(const r of manifest.resolution){const actual=sha(await bytes(tree,r.path));must(actual===r.sha256,'R4_RESOLUTION_DRIFT:'+r.path);resolution.push({...r});}
  must(eq(resolution.map(r=>r.path),resolutionPaths),'EXACT_CACHED_RESOLUTION_REQUIRED');
  const cachedSupport=[];
  must(eq(manifest.cachedSupport.map(r=>r.path),supportPaths),'EXACT_DECLARED_CACHED_SUPPORT_REQUIRED');
  for(const r of manifest.cachedSupport){must(sha(await bytes(tree,r.path))===r.sha256,'R4_CACHED_SUPPORT_DRIFT:'+r.path);cachedSupport.push({...r});}
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
    toolchain:{sdkMetadata:manifest.toolchain.sdkMetadata,tooling:toolchain},resolution,cachedSupport,bindings};
}

export function stableAudit(audit){const {checkedAt,...rest}=audit;return rest;}

// Read-only validation of an actual completed SDK result. Importing this module
// never parses process.argv and never launches a process or writes a file.
export async function auditStage(stage,{checkCurrent=true}={}){
  must(['analyzer','focusedNonGolden','goldens83','candidate8','candidate8Strict','approvedAll'].includes(stage),'R4_STAGE_INVALID');
  const recordRaw=await bytes(root,stagePath(stage)),record=parse(recordRaw),manifestPath=stage==='approvedAll'?approvedSourcePath:sourcePath;
  const manifestRaw=await bytes(root,manifestPath),manifest=parse(manifestRaw),definition=manifest.stages.find(s=>s.stage===stage);
  must(record.stage===stage&&record.revision==='r4'&&record.status==='complete'&&record.SDKExecuted===true&&record.spawnError===null&&record.integrityError===null&&
    record.sourceManifest.path===manifestPath&&record.sourceManifest.sha256===sha(manifestRaw)&&record.workingDirectory===definition.workingDirectory&&
    record.executable===sdk&&eq(record.args,definition.args)&&record.log===stageLog(stage)&&record.sdkExitRecord===stageExit(stage),'EXACT_COMPLETED_R4_STAGE_REQUIRED');
  must(Number.isFinite(Date.parse(record.startedAt))&&Date.parse(record.startedAt)<=Date.parse(record.finishedAt),'R4_STAGE_TIMES_INVALID');
  const raw=await bytes(root,record.log);must(sha(raw)===record.logSha256&&raw.length===record.logBytes,'R4_STAGE_LOG_BINDING_INVALID');
  const exitRaw=await bytes(root,record.sdkExitRecord),exit=parse(exitRaw);
  must(sha(exitRaw)===record.sdkExitRecordSha256&&exit.stage===stage&&exit.revision==='r4'&&exit.sdkExitCode===record.exitCode&&exit.spawnError===null&&exit.executable===sdk&&eq(exit.args,definition.args)&&exit.workingDirectory===definition.workingDirectory,'DURABLE_ACTUAL_R4_SDK_EXIT_REQUIRED');
  must(record.runner?.path===runnerPath&&record.runner.sha256===sha(await bytes(root,runnerPath))&&record.inputAuditor?.path===helperPath&&record.inputAuditor.sha256===sha(await bytes(root,helperPath)),'R4_STAGE_SCRIPT_BINDING_INVALID');
  for(const a of [record.inputAuditBefore,record.inputAuditAfter])must(a?.selectedSources===1068&&a.currentSourceMatchesFrozenInputs===true&&mapEq(a.sourceHashes,manifest.sourceHashes)&&
    eq(a.sourceManifest,record.sourceManifest)&&eq(a.toolchain,manifest.toolchain)&&eq(a.resolution,manifest.resolution)&&eq(a.cachedSupport,manifest.cachedSupport)&&eq(a.bindings,manifest.bindings),'R4_STAGE_PRE_POST_AUDITS_REQUIRED');
  if(stage!=='candidate8')must(eq(stableAudit(record.inputAuditBefore),stableAudit(record.inputAuditAfter)),'R4_STAGE_INPUTS_CHANGED');
  else{
    must(record.inputAuditBefore.warmSourceMatchesFrozenInputs===true&&record.inputAuditAfter.generatedImageChanges.length===8&&
      eq(record.inputAuditAfter.generatedImageChanges.map(r=>r.path).sort(),declaredGoldenFailures.map(r=>r.goldenPath).sort()),'EXACT_EIGHT_ISOLATED_GENERATED_IMAGES_REQUIRED');
    for(const key of ['sourceManifest','sourceHashes','toolchain','resolution','cachedSupport','bindings','currentInputsSha256'])must(eq(record.inputAuditBefore[key],record.inputAuditAfter[key]),'R4_GENERATION_CHANGED_FROZEN_INPUT:'+key);
  }
  let actual=null;
  if(stage==='analyzer')must(record.exitCode===0&&raw.toString('utf8').includes('No issues found!')&&record.counts===null&&eq(record.actualTestIdentities,[]),'R4_SCOPED_ANALYSIS_NOT_CLEAN');
  else{
    actual=execution(raw,definition.workingDirectory,definition.expectedTestIdentities);
    const p=actual.parsed;must(p&&p.skippedTests===0&&eq(record.counts,{passed:p.passedTests,failed:p.failedTests,skipped:0})&&
      p.passedTests+p.failedTests===definition.expectedTestIdentities.length&&eq(record.expectedTestIdentities,definition.expectedTestIdentities)&&eq(record.actualTestIdentities,actual.identities),'EXACT_R4_LOG_IDENTITIES_AND_SUMMARY_REQUIRED');
    if(stage==='goldens83')must(record.exitCode===1&&p.passedTests===75&&p.failedTests===8&&p.allTestsPassed===false&&eq(normalizedFailures(p,definition.workingDirectory),declaredGoldenFailures)&&record.strictGoldenComparisonPassed===false&&record.expectedGoldenFailuresObserved===true,'EXACT_75_PASS_EIGHT_GOLDEN_FAILURES_REQUIRED');
    else must(record.exitCode===0&&p.allTestsPassed&&p.failedTests===0&&p.failures.length===0,'R4_SELECTED_TESTS_NOT_GREEN');
    if(stage==='candidate8'||stage==='candidate8Strict')must(actual.identities.length===8&&record.approvedRepositoryImagesChanged===false,'EXACT_EIGHT_CANDIDATE_CHECKS_REQUIRED');
    if(stage==='approvedAll')must(record.fullSuitePassed===true&&actual.identities.length===2010&&record.ownerImageDecision?.path===ownerPath&&record.promotion?.path===promotionPath,'FRESH_2010_POSTAPPROVAL_SUITE_REQUIRED');
  }
  if(stage==='candidate8'){
    must(record.cases?.length===8&&new Set(record.cases.map(c=>c.approvedPath)).size===8&&eq(record.cases.map(c=>({testIdentity:c.testIdentity,goldenPath:c.approvedPath})).sort((a,b)=>a.testIdentity.localeCompare(b.testIdentity)),declaredGoldenFailures),'EXACT_CANDIDATE_EIGHT_CASES_REQUIRED');
    must(eq(record.bundle,record.candidateBundle)&&record.bundleSha256===record.candidateBundleSha256&&sha(Buffer.from(JSON.stringify(record.candidateBundle)))===record.candidateBundleSha256,'R4_CANDIDATE_BUNDLE_HASH_INVALID');
    for(const c of record.cases){
      must(c.approvedSha256===manifest.sourceHashes[c.approvedPath]&&c.candidateSha256!==c.approvedSha256&&c.approvedBackup==='build/w5verification20261010/r4/'+c.approvedPath&&c.candidatePath==='build/w5verification20261010/r4-candidate/'+c.approvedPath,'R4_CANDIDATE_PATH_OR_BASE_INVALID');
      for(const[p,h]of [[c.approvedBackup,c.approvedSha256],[c.candidatePath,c.candidateSha256],[c.diffPath,c.diffSha256]])must(sha(await bytes(root,p))===h,'R4_CANDIDATE_IMAGE_DRIFT:'+p);
    }
    must(eq(record.candidateBundle.cases,record.cases.map(({stem,testIdentity,approvedPath,approvedSha256,candidateSha256})=>({stem,testIdentity,approvedPath,approvedSha256,candidateSha256})))&&eq(record.candidateBundle.sourceManifest,record.sourceManifest)&&eq(record.candidateBundle.fullControl,record.fullControl),'R4_CANDIDATE_BUNDLE_SCOPE_INVALID');
  }
  const current=checkCurrent?await auditInputs(manifestPath,{candidate:definition.candidateTree,allowGeneratedImages:definition.candidateTree}):null;
  if(current)must(eq(stableAudit(current),stableAudit(record.inputAuditAfter)),'R4_STAGE_CURRENT_INPUTS_DRIFT');
  return{checkedAt:new Date().toISOString(),stage,record:{path:stagePath(stage),sha256:sha(recordRaw)},log:{path:record.log,sha256:sha(raw)},sourceManifest:record.sourceManifest,
    counts:record.counts,actualTestIdentities:record.actualTestIdentities,expectedTestIdentities:record.expectedTestIdentities,recordData:record,currentInputsChecked:checkCurrent};
}
