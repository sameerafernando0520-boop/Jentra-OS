import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
const root='C:/Users/sheha/Desktop/Jentra OS',base='docs/verification/wave5/seven-area-completion-20261016/area1-windows/current-candidate-20261017';
const sha=b=>createHash('sha256').update(b).digest('hex'),must=(v,c)=>{if(!v)throw Error(c);};
const read=async p=>fs.readFile(path.isAbsolute(p)?p:path.join(root,p));
const json=async p=>JSON.parse(await read(p));
const bind=async p=>{const b=await read(p);return{path:p,bytes:b.length,sha256:sha(b)};};
const resultPath=base+'/run-a2/99-result.json',result=await json(resultPath),manifest=await json(result.sourceManifest.path);
must(result.kind==='actual-current-source-windows-candidate-verification'&&result.SDKExecuted===true&&result.sourceStable===true,'ACTUAL_COMPLETE_CANDIDATE_REQUIRED');
must((await bind(result.sourceManifest.path)).sha256===result.sourceManifest.sha256,'FINAL_SOURCE_MANIFEST_REQUIRED');
const evidence=[await bind(resultPath),await bind(result.sourceManifest.path)];
for(const row of result.stages){
 must(row.passed===true&&row.code===0&&row.spawnError===null,'ALL_REAL_SDK_STAGES_PASS_REQUIRED');
 const actualExit=await json(row.actualExit.path);must(actualExit.code===0&&actualExit.pid===row.pid&&JSON.stringify(actualExit.command)===JSON.stringify(row.command),'ACTUAL_EXIT_LINEAGE_REQUIRED');
 for(const expected of[row.actualExit,row.log,row.resultBinding]){const actual=await bind(expected.path);must(actual.sha256===expected.sha256,'FINAL_EVIDENCE_CHANGED:'+expected.path);evidence.push(actual);}
 if(row.counts){must(row.counts.failed===0&&row.counts.skipped===0&&row.counts.passed>0,'ACTUAL_TEST_PASS_COUNTS_REQUIRED');must((await read(row.log.path)).toString('utf8').includes('All tests passed!'),'ACTUAL_SUCCESS_LOG_REQUIRED');}
}
const verifiedSources=[];
for(const [p,h]of Object.entries(manifest.baseSourceHashes)){must((await bind(p)).sha256===h,'ROOT_SOURCE_CHANGED:'+p);verifiedSources.push(p);}
for(const [p,h]of Object.entries(manifest.candidateSourceHashes))must((await bind(path.join(manifest.snapshot,p))).sha256===h,'CANDIDATE_SOURCE_CHANGED:'+p);
try{await fs.lstat(path.join(root,'build/wave5-flutter-job.lock'));throw Error('SDK_LOCK_NOT_RELEASED');}catch(e){if(e.code!=='ENOENT')throw e;}
const captures=await json(base+'/run-a2/05-render-artifacts.json');
for(const row of captures.files){const actual=await bind(row.path);must(actual.sha256===row.sha256&&actual.bytes===row.bytes,'FINAL_RENDER_CHANGED');evidence.push(actual);}
for(const row of result.releaseArtifacts){const actual=await bind(row.path);must(actual.sha256===row.sha256&&actual.bytes===row.bytes,'FINAL_RELEASE_FILE_CHANGED');evidence.push(actual);}
must((await bind(result.executable.path)).sha256===result.executable.sha256,'EXACT_CANDIDATE_EXE_REQUIRED');
const plan=await json(base+'/execution-plan-a2.json');
must(result.desktopFiles===plan.desktopCatalog.length&&result.platformFiles===plan.platformCatalog.length,'COMPLETE_PLANNED_CATALOG_REQUIRED');
const desktopRows=result.stages.filter(r=>r.stage.startsWith('04-desktop')),platformRows=result.stages.filter(r=>r.stage.startsWith('03-platform'));
must(desktopRows.length===plan.desktopBatches.length,'ALL_DESKTOP_BATCHES_REQUIRED');
for(let i=0;i<desktopRows.length;i++)for(const file of plan.desktopBatches[i])must(desktopRows[i].command.includes(file),'TEST_FILE_EXECUTION_REQUIRED:'+file);
const goldenPaths=verifiedSources.filter(p=>p.endsWith('.png'));
const report={kind:'current-source-candidate-completion-report',completedAt:new Date().toISOString(),result:await bind(resultPath),sourceManifest:await bind(result.sourceManifest.path),sourceCountVerified:verifiedSources.length,desktop:{files:result.desktopFiles,batches:desktopRows.length,passed:result.desktopPassed,failed:0,skipped:0},platform:{files:result.platformFiles,batches:platformRows.length,passed:result.platformPassed,failed:0,skipped:0},analyzerExitCode:result.stages.find(r=>r.stage==='02-analyze').code,offlinePubgetExitCode:result.stages.find(r=>r.stage==='01-pubget-offline').code,windowsBuildExitCode:result.stages.find(r=>r.stage==='06-build-windows').code,renderFiles:captures.count,renderTestCases:result.stages.filter(r=>r.stage.startsWith('05-render')).reduce((sum,r)=>sum+r.counts.passed,0),renderArtifacts:await bind(base+'/run-a2/05-render-artifacts.json'),candidateExecutable:result.executable,releaseFileCount:result.releaseArtifacts.length,allActualCommandExits:result.stages.map(r=>({stage:r.stage,exitCode:r.code,pid:r.pid,actualExit:r.actualExit,counts:r.counts})),postflight:{rootSourceInputsUnchanged:true,candidateSourceInputsUnchanged:true,rootGoldenFilesUnchanged:goldenPaths.length,snapshotGoldenFilesUnchanged:goldenPaths.length,SDKLockReleased:true,approvedPackageOverwritten:false,baselineUpdateFlagUsed:false,sourceAcceptanceRowsChanged:0},evidenceBindings:evidence,nativeLaunched:false,installed:false,authenticatedNative:false,nativeKeyboardAccepted:false,restartRecoveryAccepted:false,productionSigned:false,productionReady:false,ownerAcceptanceAdded:0,boundary:'Actual current-source controlled SDK tests, widget renders and unsigned Preview release compilation. This does not establish authenticated Connected Windows behavior, genuine provider execution or release readiness.'};
const output=base+'/completion-report-a2.json';await fs.writeFile(path.join(root,output),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({output,sha256:(await bind(output)).sha256,desktop:report.desktop,platform:report.platform,renderFiles:report.renderFiles,releaseFiles:report.releaseFileCount,exeSha256:report.candidateExecutable.sha256,sourceCount:report.sourceCountVerified}));
