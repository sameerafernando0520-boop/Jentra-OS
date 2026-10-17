// Disposable public-file controls only. Never runs the private adapter.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {createInterface} from 'node:readline';

const pwsh='C:/Users/sheha/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe';
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const timeout=(label,ms=10000)=>new Promise((_,reject)=>{const timer=setTimeout(()=>reject(Error(label)),ms);timer.unref();});
const denied=error=>['EPERM','EACCES','EBUSY'].includes(error?.code);

async function fixtures(){
 const directory=await fs.mkdtemp(path.join(os.tmpdir(),'JentraOS-wave5-peer-share-'));
 const payloads=[['source.mjs',Buffer.from('export const publicFixture = "readable-reviewed-source";\n')],
  ['plan.json',Buffer.from('{"publicFixture":true,"immutableWindow":true}\n')]];
 const files=[];for(const [name,bytes]of payloads){const file=path.join(directory,name);await fs.writeFile(file,bytes,{flag:'wx'});files.push({file,sha256:sha(bytes),bytes});}
 return {directory,files,async clean(){
  const resolved=path.resolve(directory),expected=path.resolve(os.tmpdir())+path.sep;
  assert.ok(resolved.startsWith(expected)&&path.basename(resolved).startsWith('JentraOS-wave5-peer-share-'),'EXACT_OWNED_DISPOSABLE_DIRECTORY_REQUIRED');
  for(const row of files)await fs.unlink(row.file).catch(error=>{if(error.code!=='ENOENT')throw error;});
  for(const name of ['replacement.tmp','renamed.tmp'])await fs.unlink(path.join(resolved,name)).catch(error=>{if(error.code!=='ENOENT')throw error;});
  await fs.rmdir(resolved);
 }};
}

function holder(files,{wrongSecondHash=false}={}){
 const config=Buffer.from(JSON.stringify(files.map((row,i)=>({path:row.file,sha256:wrongSecondHash&&i===1?'0'.repeat(64):row.sha256})))).toString('base64');
 const script=`$ErrorActionPreference='Stop'
$taskRows=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${config}'))|ConvertFrom-Json
$taskHeld=[Collections.Generic.List[IO.FileStream]]::new()
try {
 foreach($taskRow in $taskRows){
  $taskStream=[IO.File]::Open($taskRow.path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  $taskHeld.Add($taskStream)
  $taskHash=[Security.Cryptography.SHA256]::Create()
  try{$taskActual=[Convert]::ToHexString($taskHash.ComputeHash($taskStream)).ToLowerInvariant()}finally{$taskHash.Dispose()}
  $taskStream.Position=0
  if($taskActual -cne $taskRow.sha256){throw 'CONTROLLED_PUBLIC_HASH_MISMATCH'}
 }
 [Console]::Out.WriteLine('{"held":true,"fixtureCount":2}');[Console]::Out.Flush()
 $taskReply=[Console]::In.ReadLine()
 if($taskReply -ceq 'fail'){throw 'CONTROLLED_STOP_AFTER_HOLD'}
 if($taskReply -cne 'release'){throw 'CONTROLLED_RELEASE_SIGNAL_REQUIRED'}
 [Console]::Out.WriteLine('{"releasedNormally":true}')
 exit 0
}catch{
 $taskCode=if($_.Exception.Message -cmatch '^CONTROLLED_[A-Z_]+$'){$_.Exception.Message}else{'CONTROLLED_HOLDER_FAILURE'}
 [Console]::Out.WriteLine((@{stopped=$true;failureCode=$taskCode}|ConvertTo-Json -Compress))
 exit 1
}finally{foreach($taskStream in $taskHeld){$taskStream.Dispose()}}`;
 const child=spawn(pwsh,['-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',Buffer.from(script,'utf16le').toString('base64')],
  {stdio:['pipe','pipe','pipe'],windowsHide:true});
 let stdout='',stderr='';child.stdout.on('data',chunk=>{stdout+=chunk;});child.stderr.on('data',chunk=>{stderr+=chunk;});
 const close=once(child,'close');
 const lines=createInterface({input:child.stdout});
 const first=Promise.race([once(lines,'line').then(([line])=>JSON.parse(line)),timeout('CONTROLLED_HOLDER_READY_TIMEOUT')]);
 return {child,first,async finish(signal){if(signal)child.stdin.end(signal+'\n');const [code]=await Promise.race([close,timeout('CONTROLLED_HOLDER_EXIT_TIMEOUT')]);lines.close();assert.equal(stderr,'');return {code,stdout};},
  stop(){child.stdin.destroy();if(child.exitCode===null)child.kill();}};
}

async function nodeReads(files){
 const script='const fs=require("fs");const{pathToFileURL}=require("url");(async()=>{const files=JSON.parse(process.argv[1]);const bytes=files.map(p=>fs.readFileSync(p).toString("base64"));const module=await import(pathToFileURL(files[0]).href);process.stdout.write(JSON.stringify({bytes,moduleValue:module.publicFixture}));})().catch(()=>{process.stderr.write("CONTROLLED_NODE_READ_FAILED");process.exitCode=1;});';
 const child=spawn(process.execPath,['-e',script,JSON.stringify(files.map(x=>x.file))],{stdio:['ignore','pipe','pipe'],windowsHide:true});
 let stdout='',stderr='';child.stdout.on('data',chunk=>{stdout+=chunk;});child.stderr.on('data',chunk=>{stderr+=chunk;});
 const [code]=await Promise.race([once(child,'close'),timeout('CONTROLLED_NODE_READ_TIMEOUT')]);
 assert.equal(code,0);assert.equal(stderr,'');const result=JSON.parse(stdout);
 assert.deepEqual(result.bytes,files.map(row=>row.bytes.toString('base64')));assert.equal(result.moduleValue,'readable-reviewed-source');
}

for(const finalSignal of ['release','fail'])test(`Windows FileShare.Read allows Node imports and denies changes, then releases after ${finalSignal}`,async t=>{
 assert.equal(process.platform,'win32');const fixture=await fixtures();const held=holder(fixture.files);
 try{
  assert.deepEqual(await held.first,{held:true,fixtureCount:2});
  await t.test('separate Node process reads exact bytes and imports the held source',()=>nodeReads(fixture.files));
  await t.test('concurrent truncating writes are denied',async()=>{for(const row of fixture.files)await assert.rejects(fs.writeFile(row.file,'controlled mutation'),denied);});
  await t.test('concurrent writable opens are denied',async()=>{for(const row of fixture.files)await assert.rejects(fs.open(row.file,'r+'),denied);});
  await t.test('concurrent delete is denied',async()=>{for(const row of fixture.files)await assert.rejects(fs.unlink(row.file),denied);});
  await t.test('concurrent source rename is denied',()=>assert.rejects(fs.rename(fixture.files[0].file,path.join(fixture.directory,'renamed.tmp')),denied));
  await t.test('concurrent atomic replacement is denied',async()=>{const replacement=path.join(fixture.directory,'replacement.tmp');await fs.writeFile(replacement,'controlled replacement',{flag:'wx'});
   await assert.rejects(fs.rename(replacement,fixture.files[0].file),denied);assert.equal(await fs.readFile(replacement,'utf8'),'controlled replacement');});
  await t.test('all held bytes remain exact after the attempted changes',async()=>{for(const row of fixture.files)assert.equal(sha(await fs.readFile(row.file)),row.sha256);});
  const outcome=await held.finish(finalSignal);assert.equal(outcome.code,finalSignal==='release'?0:1);
  if(finalSignal==='fail')assert.ok(outcome.stdout.includes('CONTROLLED_STOP_AFTER_HOLD'));
  await t.test('handles are released and ordinary writes succeed after exit',async()=>{for(const row of fixture.files){await fs.writeFile(row.file,'after controlled release');assert.equal(await fs.readFile(row.file,'utf8'),'after controlled release');}});
 }finally{held.stop();await fixture.clean();}
});

test('hash failure after one successful hold still releases every opened handle',async()=>{
 const fixture=await fixtures(),held=holder(fixture.files,{wrongSecondHash:true});
 try{const first=await held.first;assert.equal(first.stopped,true);assert.equal(first.failureCode,'CONTROLLED_PUBLIC_HASH_MISMATCH');
  const result=await held.finish();assert.equal(result.code,1);for(const row of fixture.files){await fs.writeFile(row.file,'after controlled hash failure');assert.equal(await fs.readFile(row.file,'utf8'),'after controlled hash failure');}
 }finally{held.stop();await fixture.clean();}
});
