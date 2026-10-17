import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
const root='C:/Users/sheha/Desktop/Jentra OS';
const base='docs/verification/wave5/seven-area-completion-20261016/area1-windows/current-candidate-20261017';
const sha=b=>createHash('sha256').update(b).digest('hex'),must=(v,c)=>{if(!v)throw Error(c);};
const manifestName=process.argv[2]??'source-manifest.json';
must(process.argv.length<=3&&/^source-manifest(?:-a[2-9])?\.json$/.test(manifestName),'EXACT_CANDIDATE_MANIFEST_REQUIRED');
const suffix=manifestName==='source-manifest.json'?'':'-'+manifestName.match(/-(a\d)\./)[1];
const manifestPath=path.join(root,base,manifestName),manifestBytes=await fs.readFile(manifestPath),manifest=JSON.parse(manifestBytes);
const planName='execution-plan'+suffix+'.json',planBytes=await fs.readFile(path.join(root,base,planName)),plan=JSON.parse(planBytes);
must(plan.sourceManifest.sha256===sha(manifestBytes)&&manifest.kind==='current-source-windows-candidate-snapshot'&&manifest.mode==='Preview','EXACT_FROZEN_CANDIDATE_REQUIRED');
const snapshot=manifest.snapshot;must(snapshot.startsWith(path.join(root,'build','w5win20261017')),'OWNED_NEW_SNAPSHOT_REQUIRED');
const runBase=path.join(root,base,'run'+suffix);await fs.mkdir(runBase);
async function save(name,obj){const bytes=JSON.stringify(obj,null,2)+'\n';await fs.writeFile(path.join(runBase,name),bytes,{flag:'wx'});return{path:path.relative(root,path.join(runBase,name)).replaceAll('\\','/'),sha256:sha(bytes)};}
async function bind(absolute){const bytes=await fs.readFile(absolute);return{path:absolute,sha256:sha(bytes),bytes:bytes.length};}
async function verifySources(){for(const [p,h]of Object.entries(manifest.candidateSourceHashes))must(sha(await fs.readFile(path.join(snapshot,p)))===h,'CANDIDATE_SOURCE_DRIFT:'+p);for(const [p,h]of Object.entries(manifest.baseSourceHashes))must(sha(await fs.readFile(path.join(root,p)))===h,'CURRENT_SOURCE_DRIFT:'+p);return Object.keys(manifest.baseSourceHashes).length;}
const wrapper=path.join(root,plan.wrapper),protectedPaths=[plan.sdk,plan.tool,wrapper];
const toolPins=await Promise.all(protectedPaths.map(bind));
const startedAt=new Date().toISOString(),lockPath=path.join(root,'build/wave5-flutter-job.lock');
await verifySources();
const lock=await fs.open(lockPath,'wx');const lockBytes=Buffer.from(JSON.stringify({kind:'current-source-candidate-serialized-sdk',pid:process.pid,startedAt,runner:base+'/run-candidate.mjs',manifest:manifestName})+'\n');await lock.writeFile(lockBytes);await lock.sync();
const done=[];let activeStage=null,passed=false;
async function pins(){must(JSON.stringify(await Promise.all(protectedPaths.map(bind)))===JSON.stringify(toolPins),'SDK_OR_WRAPPER_DRIFT');}
async function stage(name,cwd,args,{capture={},tests=false}={}){
 activeStage=name;await verifySources();await pins();
 const logPath=path.join(runBase,name+'.log'),handle=await fs.open(logPath,'wx');
 const command=[process.execPath,wrapper,plan.sdk,...args],stageStartedAt=new Date().toISOString();
 const env={...process.env,DART_SUPPRESS_ANALYTICS:'true',FLUTTER_SUPPRESS_ANALYTICS:'true',CI:'true'};
 for(const key of Object.keys(env))if(key.startsWith('W5_')&&(key.includes('FRAME_DIR')||key.includes('GOLDEN_UPDATE')))delete env[key];
 for(const[key,value]of Object.entries(capture))env[key]=value;
 const child=spawn(command[0],command.slice(1),{cwd,env,windowsHide:true,stdio:['ignore',handle.fd,handle.fd]});
 const pid=child.pid??null;let spawnError=null;
 const exit=await new Promise(resolve=>{child.once('error',e=>{spawnError={code:e.code??null,message:e.message};resolve({code:127,signal:null});});child.once('close',(code,signal)=>resolve({code:code??1,signal}));});
 const finishedAt=new Date().toISOString();await handle.sync();await handle.close();
 const actualExit={kind:'actual-sdk-process-exit',stage:name,command,cwd,pid,startedAt:stageStartedAt,finishedAt,...exit,spawnError};
 const exitBinding=await save(name+'-exit.json',actualExit);
 const bytes=await fs.readFile(logPath),text=bytes.toString('utf8');
 const last=[...text.matchAll(/\d+:\d+ \+(\d+)(?: ~(\d+))?(?: -(\d+))?:/g)].at(-1);
 const counts=tests?{passed:Number(last?.[1]??0),skipped:Number(last?.[2]??0),failed:Number(last?.[3]??0)}:null;
 await verifySources();await pins();
 const stagePassed=exit.code===0&&!spawnError&&(!tests||(text.includes('All tests passed!')&&counts.passed>0&&counts.failed===0&&counts.skipped===0));
 const record={...actualExit,passed:stagePassed,counts,actualExit:exitBinding,log:{path:path.relative(root,logPath).replaceAll('\\','/'),sha256:sha(bytes),bytes:bytes.length},captureEnvironment:capture,sourceCountVerified:Object.keys(manifest.baseSourceHashes).length,sourceStable:true,goldenBaselinesUpdated:false};
 const resultBinding=await save(name+'-result.json',record);done.push({...record,resultBinding});
 console.log(JSON.stringify({stage:name,passed:stagePassed,counts,exit:exit.code}));must(stagePassed,'SDK_STAGE_FAILED:'+name);
 return record;
}
async function allFiles(dir){const out=[];for(const e of await fs.readdir(dir,{withFileTypes:true})){const p=path.join(dir,e.name);must(!e.isSymbolicLink(),'ARTIFACT_LINK_FORBIDDEN');if(e.isDirectory())out.push(...await allFiles(p));else if(e.isFile())out.push(p);}return out;}
try{
 await save('00-intent.json',{kind:'current-source-candidate-sdk-run-intent',startedAt,sourceManifest:{path:base+'/'+manifestName,sha256:sha(manifestBytes)},executionPlan:{path:base+'/'+planName,sha256:sha(planBytes)},runner:await bind(path.join(root,base,'run-candidate.mjs')),toolPins,SDKSlotGrantedByCoordinator:true,networkDownloadsAllowed:false,goldenUpdatesAllowed:false,nativeLaunched:false,privateInputsRead:false});
 await stage('01-pubget-offline',snapshot,plan.commands.pubget);
 const dependencyPins=await Promise.all(['pubspec.lock','.dart_tool/package_config.json','.dart_tool/package_graph.json'].map(p=>bind(path.join(snapshot,p))));
 await save('01-dependencies.json',{dependencyPins});protectedPaths.push(...dependencyPins.map(p=>p.path));toolPins.push(...dependencyPins);
 await stage('02-analyze',snapshot,plan.commands.analyze);
 const platformCwd=path.join(snapshot,'packages/jentra_platform'),desktopCwd=path.join(snapshot,'apps/jentra_desktop');
 for(let i=0;i<plan.platformCatalog.length;i+=6)await stage('03-platform-'+String(i/6+1).padStart(2,'0'),platformCwd,[...plan.commands.testPrefix,...plan.platformCatalog.slice(i,i+6)],{tests:true});
 for(let i=0;i<plan.desktopBatches.length;i++)await stage('04-desktop-'+String(i+1).padStart(2,'0'),desktopCwd,[...plan.commands.testPrefix,...plan.desktopBatches[i]],{tests:true});
 const captures=[];
 for(const [name,file,filter,key]of [['analytics','wave5_workspaces_test.dart','at 200%','W5_FRAME_DIR'],['continuation','wave5_continuation_test.dart','fresh render','W5_CONTINUATION_FRAME_DIR'],['model','reviewed_model_workspace_test.dart','model fresh render','W5_MODEL_FRAME_DIR']]){
  const dir=path.join(runBase,'frames-'+name);await fs.mkdir(dir);await stage('05-render-'+name,desktopCwd,[...plan.commands.testPrefix,'--name='+filter,'test/'+file],{tests:true,capture:{[key]:dir}});
  const frames=(await allFiles(dir)).filter(p=>p.endsWith('.png'));must(frames.length>0,'FRESH_RENDER_FILES_REQUIRED');
  for(const p of frames){const bytes=await fs.readFile(p);must(bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])),'VALID_PNG_REQUIRED');captures.push({path:path.relative(root,p).replaceAll('\\','/'),bytes:bytes.length,sha256:sha(bytes),width:bytes.readUInt32BE(16),height:bytes.readUInt32BE(20)});}
 }
 await save('05-render-artifacts.json',{kind:'actual-controlled-widget-render-files',files:captures,count:captures.length,visualReviewComplete:false,goldenBaselinesUpdated:false,authenticatedNative:false});
 await stage('06-build-windows',desktopCwd,plan.commands.build);
 const release=path.join(desktopCwd,'build/windows/x64/runner/Release'),artifacts=[];
 for(const p of await allFiles(release))artifacts.push({path:path.relative(root,p).replaceAll('\\','/'),...await bind(p)});
 const executable=path.join(release,'Jentra_OS.exe'),exeStat=await fs.stat(executable),exe=await bind(executable);must(exe.bytes>0&&exeStat.mtimeMs>=Date.parse(startedAt),'FRESH_CANDIDATE_EXECUTABLE_REQUIRED');
 await verifySources();await pins();
 const result={kind:'actual-current-source-windows-candidate-verification',startedAt,finishedAt:new Date().toISOString(),sourceManifest:{path:base+'/'+manifestName,sha256:sha(manifestBytes)},sourceCountVerified:Object.keys(manifest.baseSourceHashes).length,stages:done,desktopFiles:plan.desktopCatalog.length,desktopPassed:done.filter(r=>r.stage.startsWith('04-desktop')).reduce((s,r)=>s+r.counts.passed,0),platformFiles:plan.platformCatalog.length,platformPassed:done.filter(r=>r.stage.startsWith('03-platform')).reduce((s,r)=>s+r.counts.passed,0),renderFiles:captures.length,executable:{...exe,modifiedAt:exeStat.mtime.toISOString()},releaseArtifacts:artifacts,sourceStable:true,toolchainAndDependenciesStable:true,goldenBaselinesUpdated:false,nativeLaunched:false,installed:false,authenticatedNative:false,productionSigned:false,ownerAcceptance:false,SDKExecuted:true};
 await save('99-result.json',result);passed=true;console.log(JSON.stringify({completed:true,desktopPassed:result.desktopPassed,platformPassed:result.platformPassed,renderFiles:captures.length,executableSha256:exe.sha256}));
}catch(e){await save('99-stop.json',{kind:'preserved-current-candidate-sdk-stop',startedAt,stoppedAt:new Date().toISOString(),activeStage,failure:e.message,completedStages:done,complete:false,automaticRetry:false,goldenBaselinesUpdated:false});throw e;}
finally{await lock.close();try{must((await fs.readFile(lockPath)).equals(lockBytes),'OWNED_LOCK_CHANGED');await fs.unlink(lockPath);}catch(e){console.error('Owned SDK lock not removed: '+e.message);if(passed)process.exitCode=1;}}
