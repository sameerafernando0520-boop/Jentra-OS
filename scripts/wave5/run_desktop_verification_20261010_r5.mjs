// NEW r5 variant. Preserved r4 predecessor scripts/wave5/run_desktop_verification_20261010_r4.mjs SHA-256 8204c9e6c4084de2614fb6f87249ab52f6f20205a7d7b8efb387103bd533d9ec.
// Root-owned serial SDK stages. An interrupted or failed job keeps its log and
// reserved result. Only candidate8 may update exactly eight PNGs in its new copy.
import {open,readFile,unlink,writeFile} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {
  root,sourcePath,approvedSourcePath,helperPath,runnerPath,sdk,sha,eq,mapEq,must,parse,inside,bytes,
  declaredGoldenFailures,stagePath,stageLog,stageExit,execution,normalizedFailures,auditInputs,auditStage,stableAudit,
} from './desktop_verification_inputs_20261010_r5.mjs';

async function main(){
  const stage=process.argv[2];must(process.argv.length===3&&['analyzer','focusedNonGolden','goldens83','candidate8','candidate8Strict','approvedAll'].includes(stage),'R5_STAGE_INVALID');
  const manifestPath=stage==='approvedAll'?approvedSourcePath:sourcePath,manifestRaw=await bytes(root,manifestPath),manifest=parse(manifestRaw),definition=manifest.stages.find(s=>s.stage===stage);
  must(definition,'FROZEN_R5_STAGE_REQUIRED');
  const prerequisites={focusedNonGolden:['analyzer'],goldens83:['analyzer','focusedNonGolden'],candidate8:['analyzer','focusedNonGolden','goldens83'],candidate8Strict:['candidate8']};
  const verified=[];for(const p of prerequisites[stage]??[])verified.push(await auditStage(p));
  const candidate=stage.startsWith('candidate8'),before=await auditInputs(manifestPath,{candidate,allowGeneratedImages:stage==='candidate8Strict'});
  if(stage==='candidate8')must(before.warmSourceMatchesFrozenInputs===true,'CANDIDATE_TREE_MUST_BEGIN_WITH_ALL_APPROVED_IMAGES');
  const scriptStart=sha(await bytes(root,runnerPath)),helperStart=sha(await bytes(root,helperPath));
  const lockPath='build/wave5-flutter-job.lock',lockAbsolute=inside(root,lockPath),startedAt=new Date().toISOString();
  const ownership=JSON.stringify({kind:'serialized-r5-desktop-verification',pid:process.pid,stage,startedAt,runner:runnerPath})+'\n';
  const lock=await open(lockAbsolute,'wx');await lock.writeFile(ownership);await lock.sync();
  let result=null,log=null,after=null,exitCode=null,spawnError=null,integrityError=null,raw=Buffer.alloc(0),actual=[],parsed=null,exitHash=null;
  let cases=null,bundle=null,success=false,lockFailure=null;
  const resultFile=stagePath(stage),logFile=stageLog(stage),exitFile=stageExit(stage);
  try{
    result=await open(inside(root,resultFile),'wx');
    await result.writeFile(JSON.stringify({status:'in_progress',stage,revision:'r5',startedAt,sourceManifest:{path:manifestPath,sha256:sha(manifestRaw)},SDKExecuted:false,fullSuitePassed:false,boundary:'Reserved before execution; no successful test claim exists while incomplete.'},null,2)+'\n');await result.sync();
    log=await open(inside(root,logFile),'wx');
    const env={...process.env};for(const n of ['W5_CASH_FRAME_DIR','W5_MODEL_FRAME_DIR','W5_AUTH_FRAME_DIR','W5_CASH_GOLDEN_UPDATE','W5_MODEL_GOLDEN_UPDATE'])delete env[n];
    let chain=Promise.resolve();
    const child=spawn(sdk,definition.args,{cwd:definition.workingDirectory,env,windowsHide:true,stdio:['ignore','pipe','pipe']});
    for(const stream of [child.stdout,child.stderr])stream.on('data',b=>{chain=chain.then(()=>log.write(b));});
    exitCode=await new Promise(resolve=>{
      child.on('error',e=>{spawnError={message:e.message,code:e.code??null};resolve(127);});
      child.on('close',(code,signal)=>{if(signal)spawnError??={message:'SDK terminated by signal '+signal,code:signal};resolve(code??1);});
    });
    // Persist the actual SDK exit before any postflight parsing or hashing.
    const exitRecord={stage,revision:'r5',startedAt,finishedAt:new Date().toISOString(),sdkExitCode:exitCode,spawnError,executable:sdk,args:definition.args,workingDirectory:definition.workingDirectory,runner:{path:runnerPath,sha256:scriptStart}};
    const durableExit=await open(inside(root,exitFile),'wx');
    try{await durableExit.writeFile(JSON.stringify(exitRecord,null,2)+'\n');await durableExit.sync();}finally{await durableExit.close();}
    await chain;await log.sync();await log.close();log=null;
    raw=await bytes(root,logFile);exitHash=sha(await bytes(root,exitFile));
    after=await auditInputs(manifestPath,{candidate,allowGeneratedImages:candidate});
    must(sha(await bytes(root,manifestPath))===sha(manifestRaw)&&sha(await bytes(root,runnerPath))===scriptStart&&sha(await bytes(root,helperPath))===helperStart,'R5_MANIFEST_OR_RUNNER_CHANGED_DURING_STAGE');
    if(stage==='candidate8'){
      for(const key of ['sourceManifest','sourceHashes','currentInputsSha256','toolchain','resolution','cachedSupport','bindings'])must(eq(before[key],after[key]),'R5_GENERATION_CHANGED_FROZEN_INPUT:'+key);
      must(after.generatedImageChanges.length===8&&eq(after.generatedImageChanges.map(r=>r.path).sort(),declaredGoldenFailures.map(r=>r.goldenPath).sort()),'ONLY_EXACT_EIGHT_ISOLATED_PNG_CHANGES_ALLOWED');
    }else must(eq(stableAudit(before),stableAudit(after)),'R5_SOURCE_SDK_OR_RESOLUTION_CHANGED_DURING_STAGE');
    if(stage==='analyzer')must(exitCode===0&&!spawnError&&raw.toString('utf8').includes('No issues found!'),'SCOPED_R5_ANALYSIS_NOT_CLEAN');
    else{
      const run=execution(raw,definition.workingDirectory,definition.expectedTestIdentities);actual=run.identities;parsed=run.parsed;
      must(parsed&&parsed.skippedTests===0&&parsed.passedTests+parsed.failedTests===definition.expectedTestIdentities.length,'EXACT_SELECTED_R5_TEST_COUNTS_REQUIRED');
      if(stage==='goldens83')must(exitCode===1&&!spawnError&&parsed.passedTests===75&&parsed.failedTests===8&&parsed.allTestsPassed===false&&eq(normalizedFailures(parsed,definition.workingDirectory),declaredGoldenFailures),'STRICT_R5_CONTROL_REQUIRES_ONLY_EXACT_EIGHT_GOLDEN_FAILURES');
      else must(exitCode===0&&!spawnError&&parsed.allTestsPassed&&parsed.failedTests===0&&parsed.failures.length===0,'R5_TEST_STAGE_NOT_GREEN');
    }
    if(stage==='candidate8'){
      const control=verified.find(v=>v.stage==='goldens83');must(control,'ACTUAL_STRICT83_CONTROL_REQUIRED');
      cases=[];
      for(const row of declaredGoldenFailures){
        const stem=path.basename(row.goldenPath,'.png'),approvedBackup='build/w5verification20261010/r5/'+row.goldenPath,
          candidatePath='build/w5verification20261010/r5-candidate/'+row.goldenPath,
          diffPath='build/w5verification20261010/r5/apps/jentra_desktop/test/failures/'+stem+'_isolatedDiff.png',
          testImagePath='build/w5verification20261010/r5/apps/jentra_desktop/test/failures/'+stem+'_testImage.png',
          masterPath='build/w5verification20261010/r5/apps/jentra_desktop/test/failures/'+stem+'_masterImage.png';
        const proposed=await bytes(root,candidatePath),original=await bytes(root,approvedBackup),diff=await bytes(root,diffPath);
        must(proposed.subarray(0,8).toString('hex')==='89504e470d0a1a0a'&&original.subarray(0,8).toString('hex')==='89504e470d0a1a0a'&&diff.subarray(0,8).toString('hex')==='89504e470d0a1a0a','REAL_PNG_CANDIDATE_AND_COMPARISON_REQUIRED');
        must(sha(original)===manifest.sourceHashes[row.goldenPath]&&sha(await bytes(root,masterPath))===sha(original)&&sha(await bytes(root,testImagePath))===sha(proposed),'CANDIDATE_MUST_MATCH_ACTUAL_STRICT_CONTROL_RENDER:'+stem);
        cases.push({stem,testIdentity:row.testIdentity,goldenPath:row.goldenPath,approvedPath:row.goldenPath,approvedSha256:sha(original),approvedBackup,
          candidatePath,candidateSha256:sha(proposed),diffPath,diffSha256:sha(diff),controlTestImage:{path:testImagePath,sha256:sha(proposed)},
          dimensions:[proposed.readUInt32BE(16),proposed.readUInt32BE(20)]});
      }
      bundle={revision:'r5',sourceManifest:{path:manifestPath,sha256:sha(manifestRaw)},fullControl:control.record,
        controlScope:'Strict comparison of the exact earlier 83 approved image cases; 75 passed and 8 proposed Preview guidance comparisons failed.',
        cases:cases.map(({stem,testIdentity,approvedPath,approvedSha256,candidateSha256})=>({stem,testIdentity,approvedPath,approvedSha256,candidateSha256}))};
    }
    success=true;
  }catch(e){integrityError=e.message;}
  finally{
    if(log)try{await log.sync();await log.close();}catch(e){integrityError??=e.message;}
    if(!raw.length)try{raw=await bytes(root,logFile);}catch{}
    if(!parsed&&stage!=='analyzer')try{parsed=execution(raw,definition.workingDirectory,definition.expectedTestIdentities).parsed;}catch{}
    try{await lock.close();must((await readFile(lockAbsolute,'utf8'))===ownership,'R5_JOB_LOCK_OWNERSHIP_CHANGED');await unlink(lockAbsolute);}catch(e){lockFailure=e.message;integrityError??=e.message;success=false;}
  }
  const complete=success&&!integrityError&&!spawnError,counts=parsed?{passed:parsed.passedTests,failed:parsed.failedTests,skipped:parsed.skippedTests}:null;
  const report={stage,revision:'r5',status:complete?'complete':'failed',startedAt,finishedAt:new Date().toISOString(),workingDirectory:definition.workingDirectory,
    executable:sdk,args:definition.args,SDKExecuted:exitCode!==null,sourceManifest:{path:manifestPath,sha256:sha(manifestRaw)},log:logFile,logSha256:sha(raw),logBytes:raw.length,
    exitCode,spawnError,integrityError,counts,expectedTestIdentities:definition.expectedTestIdentities,actualTestIdentities:actual,
    inputAuditBefore:before,inputAuditAfter:after,runner:{path:runnerPath,sha256:scriptStart},inputAuditor:{path:helperPath,sha256:helperStart},
    sdkExitRecord:exitCode!==null?exitFile:null,sdkExitRecordSha256:exitHash,prerequisites:verified.map(v=>v.record),cooperativeLockRemoved:lockFailure===null,
    fullSuitePassed:stage==='approvedAll'&&complete&&actual.length===2010,
    strictGoldenComparisonPassed:stage==='goldens83'?false:stage==='candidate8Strict'||stage==='approvedAll'?complete:null,
    expectedGoldenFailuresObserved:stage==='goldens83'&&complete,goldenFilesRegenerated:stage==='candidate8'&&complete,
    candidateImagesRegenerated:stage==='candidate8'&&complete?8:0,approvedRepositoryImagesChanged:false,ownerAcceptanceChanged:false,
    ...(stage==='approvedAll'?{ownerImageDecision:manifest.ownerImageDecision,promotion:manifest.promotion,approvedImageChanges:8}:{}),
    ...(stage==='candidate8'?{fullControl:verified.find(v=>v.stage==='goldens83')?.record??null,cases,candidateBundle:bundle,candidateBundleSha256:bundle?sha(Buffer.from(JSON.stringify(bundle))):null,bundle,bundleSha256:bundle?sha(Buffer.from(JSON.stringify(bundle))):null}:{}),
    ...(stage==='candidate8Strict'?{candidateGeneration:verified.find(v=>v.stage==='candidate8')?.record??null}:{}),
    boundary:'Actual controlled SDK verification only. Expected strict failures remain failures; candidate regeneration is isolated and is not approval. Installed SQL, authenticated native, MFA, actual delivery/model use, contention/load, owner acceptance, production and billing remain separate.'};
  if(result)try{await result.truncate(0);await result.write(JSON.stringify(report,null,2)+'\n',0,'utf8');await result.sync();}finally{await result.close();}
  if(complete)await auditStage(stage);
  console.log(JSON.stringify({stage,status:report.status,counts,actualSDKExit:exitCode,integrityError,fullSuitePassed:report.fullSuitePassed,
    strictGoldenComparisonPassed:report.strictGoldenComparisonPassed,expectedGoldenFailuresObserved:report.expectedGoldenFailuresObserved,candidateImagesRegenerated:report.candidateImagesRegenerated,
    result:resultFile,resultSha256:result?sha(await bytes(root,resultFile)):null,log:logFile}));
  if(!complete)process.exitCode=1;
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))await main();
