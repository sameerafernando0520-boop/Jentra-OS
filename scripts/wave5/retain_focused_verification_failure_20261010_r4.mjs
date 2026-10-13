// Preserve only root's failed SDK-start attempt before a serialized cache-access retry.
// No SDK, product source, approved images, dependency lock or application store writes.
import {lstat, open, readFile, realpath, rename} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const base='docs/verification/wave5/';
const oldStem=base+'desktop-verification-focusedNonGolden-20261010-r4';
const newStem=base+'desktop-verification-focusedNonGolden-20261010-r4-a1-failed';
const journalPath=base+'desktop-verification-focused-retention-20261010-r4-a1.json';
const hash=b=>createHash('sha256').update(b).digest('hex');
const must=(ok,msg)=>{if(!ok)throw Error(msg);};
const pins={'.json':'94076f0baa3301e357218e3bed65ac0cefee3957ea51f578657ede8694b61029',
  '.log':'b598a76f2aa7104d8e392f8ef7bb0d5214f146326070b3e3a035be575d93e3c8',
  '.sdk-exit.json':'d4230b9d8b3f7fc44e7463748d37f05a519b255556acaad9978ca63df1ef98ee'};
const absolute=relative=>{
  const target=path.resolve(root,relative);
  must(path.dirname(target)===path.join(root,'docs/verification/wave5'),'EXACT_VERIFICATION_DIRECTORY_REQUIRED');
  return target;
};
const missing=async relative=>{try{await lstat(absolute(relative));return false;}catch(e){if(e.code==='ENOENT')return true;throw e;}};
must(process.argv.length===2,'NO_ARGUMENTS_REQUIRED');
must(await realpath(path.join(root,'docs/verification/wave5'))===path.join(root,'docs/verification/wave5'),'VERIFICATION_DIRECTORY_LINK_REFUSED');
try{await lstat(path.join(root,'build/wave5-flutter-job.lock'));throw Error('SDK_JOB_MUST_BE_IDLE');}catch(e){if(e.code!=='ENOENT')throw e;}
const planned=[];
for(const [suffix,sha256] of Object.entries(pins)){
  const originalPath=oldStem+suffix,retainedPath=newStem+suffix;
  const stat=await lstat(absolute(originalPath));
  must(stat.isFile()&&!stat.isSymbolicLink()&&await realpath(absolute(originalPath))===absolute(originalPath),'OWNED_REGULAR_FAILED_FILE_REQUIRED');
  must(hash(await readFile(absolute(originalPath)))===sha256,'EXACT_FAILED_ATTEMPT_BYTES_REQUIRED');
  must(await missing(retainedPath),'NEW_RETAINED_PATH_REQUIRED');
  planned.push({originalPath,retainedPath,sha256,bytes:stat.size});
}
const failed=JSON.parse(await readFile(absolute(oldStem+'.json'),'utf8'));
must(failed.status==='failed'&&failed.stage==='focusedNonGolden'&&failed.exitCode===3221225480&&failed.actualTestIdentities.length===0&&failed.cooperativeLockRemoved===true,'EXACT_NO_TEST_EXECUTION_FAILURE_REQUIRED');
must(await missing(journalPath),'NEW_RETENTION_JOURNAL_REQUIRED');
const startedAt=new Date().toISOString(),journal=await open(absolute(journalPath),'wx'),moved=[];
let failure=null;
try{
  await journal.writeFile(JSON.stringify({status:'in_progress',startedAt,planned,reason:'Sandbox SDK cache lock access failed before any focused test started.'},null,2)+'\n');await journal.sync();
  for(const item of planned){
    must(await missing(item.retainedPath)&&hash(await readFile(absolute(item.originalPath)))===item.sha256,'RETENTION_INPUT_CHANGED');
    await rename(absolute(item.originalPath),absolute(item.retainedPath));
    moved.push(item.originalPath);
    must(hash(await readFile(absolute(item.retainedPath)))===item.sha256&&await missing(item.originalPath),'RETAINED_BYTES_OR_SOURCE_ABSENCE_MISMATCH');
  }
}catch(e){failure=e.message;}
const observed=[];
for(const item of planned){
  let retainedSha256=null,retainedBytes=null,error=null;
  try{const raw=await readFile(absolute(item.retainedPath));retainedSha256=hash(raw);retainedBytes=raw.length;}catch(e){error=e.message;}
  observed.push({...item,originalAbsent:await missing(item.originalPath),retainedSha256,retainedBytes,
    retainedBytesMatch:retainedSha256===item.sha256&&retainedBytes===item.bytes,error});
}
const complete=failure===null&&observed.length===3&&observed.every(r=>r.originalAbsent&&r.retainedBytesMatch&&!r.error);
const record={status:complete?'complete':'failed',startedAt,finishedAt:new Date().toISOString(),failure,
  preservedFailedAttempt:true,allThreeFailedFilesRetained:complete,moved,observed,
  historicalReferenceMapping:planned.map(r=>({originalPath:r.originalPath,retainedPath:r.retainedPath,sha256:r.sha256})),
  failedSDKExitCode:failed.exitCode,actualFocusedTestsStarted:0,sharedSourceChanged:false,approvedImagesChanged:false,
  dependencyLockChanged:false,acceptanceStoresOrSessionsAccessed:false,SDKExecuted:false,
  boundary:'The retained failed JSON keeps its original log paths verbatim. Read those historical references through this exact mapping; a subsequent retry may recreate the absent original stage paths. No failed evidence bytes were discarded or rewritten, and this retention makes no passing test claim.'};
try{await journal.truncate(0);await journal.write(JSON.stringify(record,null,2)+'\n',0,'utf8');await journal.sync();}finally{await journal.close();}
console.log(JSON.stringify({complete,journalPath,preservedFiles:observed.filter(r=>r.retainedBytesMatch).length,failure}));
if(!complete)process.exitCode=1;
