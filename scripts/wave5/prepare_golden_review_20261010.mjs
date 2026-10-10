import {copyFile, lstat, mkdir, readFile, readdir, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {sources} from './cash_ui_evidence.mjs';
import {parseTestLog} from './record_continuation_windows.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const base='docs/verification/wave5/';
const snapshot=path.join(root,'build/w5goldens20261010/r1');
const manifest=base+'golden-review-source-20261010-r1.json';
const members=['apps/jentra_desktop','packages/jentra_domain','packages/jentra_platform','packages/jentra_design_system'];
const select=hashes=>Object.fromEntries(Object.entries(hashes).filter(([p])=>
  ['pubspec.yaml','pubspec.lock','analysis_options.yaml'].includes(p)||members.some(m=>p.startsWith(m+'/'))||/^apps\/[^/]+\/pubspec.yaml$/.test(p)));
const sha=b=>createHash('sha256').update(b).digest('hex');
const exists=async p=>{try{await lstat(p);return true;}catch(e){if(e.code==='ENOENT')return false;throw e;}};
const json=async p=>JSON.parse(await readFile(path.join(root,p),'utf8'));
const write=async(p,v)=>writeFile(path.join(root,p),JSON.stringify(v,null,2)+'\n',{flag:'wx'});
const mode=process.argv[2]??'snapshot';
if(mode==='snapshot'){
  if(await exists(snapshot)||await exists(path.join(root,manifest)))throw Error('NEW_GOLDEN_SNAPSHOT_REQUIRED');
  const before=select(await sources(root));
  const r13=await json(base+'windows-test-preview-source-20261009-r13.json');
  const delta=Object.keys(before).filter(p=>r13.baseSourceHashes[p]!==before[p]).map(p=>({path:p,r13Sha256:r13.baseSourceHashes[p]??null,currentSha256:before[p]}));
  await mkdir(snapshot,{recursive:true});
  for(const[p,h]of Object.entries(before)){
    const target=path.join(snapshot,p);await mkdir(path.dirname(target),{recursive:true});
    await copyFile(path.join(root,p),target);
    if(sha(await readFile(target))!==h)throw Error('SOURCE_COPY_DRIFT');
  }
  const after=select(await sources(root));
  if(JSON.stringify(before)!==JSON.stringify(after))throw Error('CONCURRENT_SOURCE_CHANGE');
  const scriptPath='scripts/wave5/prepare_golden_review_20261010.mjs';
  await write(manifest,{capturedAt:new Date().toISOString(),workspace:root,snapshot,gitHead:execFileSync('git',['rev-parse','HEAD'],{cwd:root,encoding:'utf8'}).trim(),
    sourceHashes:before,selectedSourceCount:Object.keys(before).length,deltaFromR13:delta,
    script:{path:scriptPath,sha256:sha(await readFile(path.join(root,scriptPath)))},
    dependencyScope:members,sourceStable:true,overlays:[],storesCopied:false,sharedSourceChanged:false,
    boundary:'Frozen current desktop inputs and every workspace manifest. No acceptance state, credentials, generated output, image update or source repair. Prior r13 is historical where inputs differ.'});
  console.log(JSON.stringify({snapshot,count:Object.keys(before).length,deltaFromR13:delta,sourceStable:true}));
}else if(mode==='candidate'){
  const m=await json(manifest),comparison=await json(base+'continuation-goldens-comparison-20261009-r13.json');
  const current=select(await sources(root));
  if(JSON.stringify(current)!==JSON.stringify(m.sourceHashes))throw Error('CURRENT_SOURCE_DRIFT');
  const copied=select(await sources(snapshot));
  if(JSON.stringify(copied)!==JSON.stringify(m.sourceHashes))throw Error('SNAPSHOT_SOURCE_DRIFT');
  const groupCounts={};for(const c of comparison.cases)groupCounts[c.classification]=(groupCounts[c.classification]??0)+1;
  if(comparison.cases.length!==83||new Set(comparison.cases.map(c=>c.stem)).size!==83||new Set(comparison.cases.map(c=>c.approved)).size!==83||
    groupCounts['localized-border-raster']!==65||groupCounts['capability-navigation-and-border-raster']!==16||groupCounts['payroll-content-change']!==2)throw Error('CASE_SET_CHANGED');
  const stage=await json(base+'golden-review-controlAll-20261010-r1.json');
  if(stage.exitCode!==1)throw Error('CONTROL_EXPECTED_83_FAILURES');
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
    const candidatePath=base+'golden-review-candidates-20261010-r1/'+c.stem+'.png';
    const approvedBackup=base+'golden-review-approved-20261010-r1/'+c.stem+'.png';
    const diffCopy=base+'golden-review-diffs-20261010-r1/'+c.stem+'.png';
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
  const candidateManifest=base+'golden-review-candidate-20261010-r1.json';
  const sourceManifestSha=sha(await readFile(path.join(root,manifest)));
  const bundle={sourceManifest:{path:manifest,sha256:sourceManifestSha},control:{path:base+'golden-review-controlAll-20261010-r1.json',sha256:sha(await readFile(path.join(root,base+'golden-review-controlAll-20261010-r1.json')))},
    cases:cases.map(c=>({stem:c.stem,approvedPath:c.approvedPath,approvedSha256:c.approvedSha256,candidateSha256:c.candidateSha256}))};
  const bundleSha256=sha(Buffer.from(JSON.stringify(bundle)));
  await write(candidateManifest,{preparedAt:new Date().toISOString(),snapshot,sourceManifest:bundle.sourceManifest,control:bundle.control,bundleSha256,bundle,cases,
    counts:{cases:cases.length,freshMatchesR13:cases.filter(c=>c.freshMatchesR13).length},
    comparatorChanged:false,fixturePermissionsChanged:false,approvedRepositoryImagesChanged:false,ownerAccepted:false,
    boundary:'83 explicitly diagnosed image overlays in an isolated test copy only. A green candidate run cannot approve itself or satisfy native/runtime/owner gates.'});
  console.log(JSON.stringify({cases:cases.length,freshMatchesR13:cases.filter(c=>c.freshMatchesR13).length,bundleSha256,approvedRepositoryImagesChanged:false}));
}else throw Error('MODE_INVALID');
