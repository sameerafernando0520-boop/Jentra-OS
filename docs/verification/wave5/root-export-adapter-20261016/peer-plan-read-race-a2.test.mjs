// Public disposable proof of the a2 hash/parse/hold ordering gap.
// Does not execute the private adapter or touch private inputs/network.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {createInterface} from 'node:readline';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../../../../',import.meta.url));
const pwsh='C:/Users/sheha/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe';
const hash=x=>createHash('sha256').update(x).digest('hex');
const locks=await fs.readFile(path.join(root,'docs/verification/wave5/root-export-adapter-20261016/public-read-holds-a2.ps1'),'utf8');
assert.equal(hash(locks),'f8b82f70c0cce59208ebe670459e5cc2dbffede6496a238524a7b8f277f44388');
const bounded=promise=>Promise.race([promise,new Promise((_,reject)=>{const timer=setTimeout(()=>reject(Error('CONTROLLED_PUBLIC_RACE_TIMEOUT')),10000);timer.unref();})]);

test('controlled concurrent replacement proves a2 can hold the approved plan while trusting a different cached inventory',async()=>{
 assert.equal(process.platform,'win32');
 const directory=await fs.mkdtemp(path.join(os.tmpdir(),'JentraOS-wave5-peer-plan-race-'));
 const dependency=path.join(directory,'dependency.mjs'),planFile=path.join(directory,'plan.json');
 const originalSource=Buffer.from('export const publicDependency = "original";\n');
 const approved=Buffer.from(JSON.stringify({sourceBindings:[{path:'dependency.mjs',sha256:hash(originalSource)}],publicBindings:[],window:{fixtureOnly:true}}));
 const transient=Buffer.from(JSON.stringify({sourceBindings:[],publicBindings:[],window:{fixtureOnly:true}}));
 await fs.writeFile(dependency,originalSource,{flag:'wx'});await fs.writeFile(planFile,approved,{flag:'wx'});
 const config=Buffer.from(JSON.stringify({base:directory,plan:planFile})).toString('base64');
 const script=`$ErrorActionPreference='Stop'
${locks}
$taskFixture=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${config}'))|ConvertFrom-Json
try {
 # Same public ordering as frozen a2: hash, parse, inventory holds, plan hold.
 $taskExportPlanSha=(Get-FileHash -LiteralPath $taskFixture.plan -Algorithm SHA256).Hash.ToLowerInvariant()
 [Console]::Out.WriteLine((@{phase='hashed';sha256=$taskExportPlanSha}|ConvertTo-Json -Compress));[Console]::Out.Flush()
 $null=[Console]::In.ReadLine()
 $taskExportPlan=Get-Content -Raw -LiteralPath $taskFixture.plan|ConvertFrom-Json -DateKind String
 [Console]::Out.WriteLine((@{phase='parsed';cachedSources=@($taskExportPlan.sourceBindings).Count}|ConvertTo-Json -Compress));[Console]::Out.Flush()
 $null=[Console]::In.ReadLine()
 foreach($taskBinding in @($taskExportPlan.sourceBindings)){Add-TaskReviewedReadHold $taskFixture.base $taskBinding.path $taskBinding.sha256}
 foreach($taskBinding in @($taskExportPlan.publicBindings)){Add-TaskReviewedReadHold $taskFixture.base $taskBinding.path $taskBinding.sha256}
 Add-TaskReviewedReadHold $taskFixture.base 'plan.json' $taskExportPlanSha
 [Console]::Out.WriteLine((@{phase='held';cachedSources=@($taskExportPlan.sourceBindings).Count;approvedPlanSha256=(Get-FileHash -LiteralPath $taskFixture.plan -Algorithm SHA256).Hash.ToLowerInvariant()}|ConvertTo-Json -Compress));[Console]::Out.Flush()
 $null=[Console]::In.ReadLine()
 exit 0
}finally{Close-TaskReviewedReadHolds}`;
 const child=spawn(pwsh,['-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',Buffer.from(script,'utf16le').toString('base64')],{stdio:['pipe','pipe','pipe'],windowsHide:true});
 let stderr='';child.stderr.on('data',x=>{stderr+=x;});const closed=once(child,'close');
 const lines=createInterface({input:child.stdout}),iterator=lines[Symbol.asyncIterator]();
 const next=async()=>{const value=await bounded(iterator.next());assert.equal(value.done,false);return JSON.parse(value.value);};
 try{
  const hashed=await next();assert.deepEqual(hashed,{phase:'hashed',sha256:hash(approved)});
  await fs.writeFile(planFile,transient);child.stdin.write('parse transient public fixture\n');
  assert.deepEqual(await next(),{phase:'parsed',cachedSources:0});
  await fs.writeFile(planFile,approved);child.stdin.write('hold approved public fixture\n');
  assert.deepEqual(await next(),{phase:'held',cachedSources:0,approvedPlanSha256:hash(approved)});
  // The held approved plan names dependency.mjs, but the cached inventory did not.
  await fs.writeFile(dependency,'controlled mutation while approved plan is held');
  assert.equal(await fs.readFile(dependency,'utf8'),'controlled mutation while approved plan is held');
  assert.equal(hash(await fs.readFile(planFile)),hash(approved));
  child.stdin.end('release controlled public holds\n');const [exitCode]=await bounded(closed);assert.equal(exitCode,0);assert.equal(stderr,'');
 }finally{
  lines.close();child.stdin.destroy();if(child.exitCode===null){child.kill();await bounded(closed);}
  const resolved=path.resolve(directory);assert.ok(resolved.startsWith(path.resolve(os.tmpdir())+path.sep)&&path.basename(resolved).startsWith('JentraOS-wave5-peer-plan-race-'));
  await fs.unlink(dependency);await fs.unlink(planFile);await fs.rmdir(resolved);
 }
});
