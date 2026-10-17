// Independent source and disposable public-file race controls. No private adapter execution.
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
import {buildCandidate,PREDECESSOR} from '../../../../tools/wave5/prepare_export_private_adapter_20261017_r5_a3.mjs';
const root=fileURLToPath(new URL('../../../../',import.meta.url));
const pwsh='C:/Users/sheha/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe';
const hash=x=>createHash('sha256').update(x).digest('hex');
const read=file=>fs.readFile(path.join(root,file));
const [a3Bytes,a2Bytes,before,locksBytes,sourceBytes]=await Promise.all([
 read('scripts/wave5/run_private_management_installer_20261017_r5_a3.candidate.ps1'),
 read('scripts/wave5/run_private_management_installer_20261016_r5_a2.candidate.ps1'),read(PREDECESSOR.path),
 read('docs/verification/wave5/root-export-adapter-20261016/public-read-holds-a2.ps1'),
 read('tools/wave5/finance_exports_20261016_r5_a7.mjs')]);
const a3=a3Bytes.toString('utf8'),a2=a2Bytes.toString('utf8'),locks=locksBytes.toString('utf8');
const reviewHold="            Add-TaskReviewedReadHold $taskRoot 'docs/verification/wave5/task3-export-renewal-20261016/final-operation-review-a1.json' $ExportFinalReviewSha256\n";
const planHold="            Add-TaskReviewedReadHold $taskExecutionRoot 'docs/verification/wave5/finance-exports-preparation-20261016-r5-a7.json' $taskExportReview.generatedPlan.sha256\n";

test('frozen a3, a2, predecessor, helper and A7 source hashes match',()=>{
 for(const [bytes,expected]of [[a3Bytes,'aba5237681017897064118d2529c9401d92e6054257a19d4c01a6196f076dcf3'],
  [a2Bytes,'4dd4911e892fa75dfdaaa0e0ea9036ddaa2e93d5a040c736515b55cec9053c15'],[before,PREDECESSOR.sha256],
  [locksBytes,'f8b82f70c0cce59208ebe670459e5cc2dbffede6496a238524a7b8f277f44388'],
  [sourceBytes,'ec1cbf544b2974db26b1fcb25a04fc1d54610e7149090a3dcbd5c185adb247c6']])assert.equal(hash(bytes),expected);
});
test('pure additive a3 builder reproduces the exact candidate without running it',()=>{
 assert.equal(buildCandidate(before,hash(sourceBytes),locks).text,a3);
 assert.throws(()=>buildCandidate(Buffer.concat([before,Buffer.from('\n')]),hash(sourceBytes),locks),/EXACT_PRESERVED_PRIVATE_ADAPTER_REQUIRED/);
});
test('exact a2 to a3 adapter delta consists only of the two early verified holds',()=>{
 assert.equal(a3.split(reviewHold).length,2);assert.equal(a3.split(planHold).length,2);
 assert.equal(a3.replace(reviewHold,'').replace(planHold,''),a2);
});
test('pinned review and plan holds precede reads and inventory/window derivation',()=>{
 const reviewLocked=a3.indexOf(reviewHold),reviewParsed=a3.indexOf('$taskExportReview = Get-Content');
 const planLocked=a3.indexOf(planHold),planHashed=a3.indexOf('$taskExportPlanSha = (Get-FileHash');
 const planParsed=a3.indexOf('$taskExportPlan = Get-Content'),window=a3.indexOf('$taskExportWindow = $taskExportPlan.window');
 const inventory=a3.indexOf('foreach ($taskBinding in @($taskExportPlan.sourceBindings))');
 assert.ok(reviewLocked>0&&reviewLocked<reviewParsed&&reviewParsed<planLocked&&planLocked<planHashed&&planHashed<planParsed&&planParsed<window&&window<inventory);
});
test('full reviewed inventory remains held before preflight and final source/plan checks precede DPAPI',()=>{
 const inventory=a3.indexOf('foreach ($taskBinding in @($taskExportPlan.sourceBindings))'),preflight=a3.indexOf("$taskPhase = 'public-export-preflight'");
 const section=a3.slice(inventory,preflight);for(const value of ['@($taskExportPlan.publicBindings)',
  "'tools/wave5/finance_exports_20261016_r5_a7.mjs'","'docs/verification/wave5/finance-exports-preparation-20261016-r5-a7.json'",
  "'docs/verification/wave5/task3-export-renewal-20261016/final-operation-review-a1.json'",
  "'docs/verification/wave5/approved-isolated-execution-snapshot-20261013-r5-a2.json'",'$taskRoot $taskSelfRelative'])assert.ok(section.includes(value),value);
 const guard=a3.slice(a3.indexOf("throw 'PRIVATE_METADATA_CHANGED'"),a3.indexOf('$taskSecret = ConvertTo-SecureString -String'));
 for(const value of ['$taskReadyFile','$taskExportReviewFile','$taskInstaller','$taskExportPlanPath','$taskExportStart','$taskExportEnd'])assert.ok(guard.includes(value),value);
});
test('validation, reviewed window, child lifetime and cleanup remain bound',()=>{
 const privateList=a3.split('\n').find(line=>line.startsWith('$taskNeedsPrivate ='));
 assert.ok(!privateList.includes('ValidateExportsA7'));assert.ok(privateList.includes('ExecuteExportsA7'));
 assert.ok(a3.indexOf("if ($Mode -eq 'ValidateExportsA7')")<a3.indexOf("$taskPhase = 'private-metadata-validation'"));
 assert.ok(a3.includes('Add-Member -NotePropertyName exportWindow -NotePropertyValue $taskExportWindow'));
 const cleanup=a3.slice(a3.indexOf('} finally {\n    $taskPlain = $null'));
 assert.ok(cleanup.includes('$taskChild.Kill($true)'));assert.ok(cleanup.includes('$taskChild.WaitForExit(10000)'));
 assert.ok(cleanup.includes('} finally { Close-TaskReviewedReadHolds }'));
});

const bounded=promise=>Promise.race([promise,new Promise((_,reject)=>{const timer=setTimeout(()=>reject(Error('CONTROLLED_EARLY_HOLD_TIMEOUT')),10000);timer.unref();})]);
const denied=error=>['EPERM','EACCES','EBUSY'].includes(error?.code);
for(const kind of ['review','plan'])for(const replaceBeforeHold of [false,true])test(`${kind}: ${replaceBeforeHold?'wrong bytes are rejected before parsing':'replacement after the verified hold is denied and approved bytes are parsed'}`,async()=>{
 assert.equal(process.platform,'win32');const directory=await fs.mkdtemp(path.join(os.tmpdir(),'JentraOS-wave5-peer-early-hold-'));
 const file=path.join(directory,kind+'.json'),bytes=Buffer.from(JSON.stringify({kind,sourceBindings:[{path:'dependency.mjs',sha256:hash('controlled dependency')}]}));
 await fs.writeFile(file,replaceBeforeHold?'transient unapproved bytes':bytes,{flag:'wx'});
 const config=Buffer.from(JSON.stringify({base:directory,relative:kind+'.json',file,sha256:hash(bytes)})).toString('base64');
 const script=`$ErrorActionPreference='Stop'
${locks}
$taskFixture=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${config}'))|ConvertFrom-Json
$taskParsed=$false
try {
 # This is the verified-hold-before-read order added by the exact a3 delta.
 Add-TaskReviewedReadHold $taskFixture.base $taskFixture.relative $taskFixture.sha256
 [Console]::Out.WriteLine('{"held":true}');[Console]::Out.Flush()
 $null=[Console]::In.ReadLine()
 $taskCached=Get-Content -Raw -LiteralPath $taskFixture.file|ConvertFrom-Json -DateKind String
 $taskParsed=$true
 [Console]::Out.WriteLine((@{parsed=$true;cachedSources=@($taskCached.sourceBindings).Count;kind=$taskCached.kind}|ConvertTo-Json -Compress))
 exit 0
}catch{[Console]::Out.WriteLine((@{parsed=$taskParsed;failureCode=$_.Exception.Message}|ConvertTo-Json -Compress));exit 1
}finally{Close-TaskReviewedReadHolds}`;
 const child=spawn(pwsh,['-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',Buffer.from(script,'utf16le').toString('base64')],{stdio:['pipe','pipe','pipe'],windowsHide:true});
 let stderr='';child.stderr.on('data',x=>{stderr+=x;});const closed=once(child,'close');
 const lines=createInterface({input:child.stdout}),iterator=lines[Symbol.asyncIterator]();
 const next=async()=>{const value=await bounded(iterator.next());assert.equal(value.done,false);return JSON.parse(value.value);};
 try{
  if(replaceBeforeHold){assert.deepEqual(await next(),{parsed:false,failureCode:'REVIEWED_FILE_HASH_CHANGED'});assert.equal((await bounded(closed))[0],1);}
  else{assert.deepEqual(await next(),{held:true});await assert.rejects(fs.writeFile(file,'transient replacement'),denied);
   child.stdin.end('parse held public file\n');assert.deepEqual(await next(),{parsed:true,cachedSources:1,kind});assert.equal((await bounded(closed))[0],0);}
  assert.equal(stderr,'');await fs.writeFile(file,'after controlled handle release');
 }finally{
  lines.close();child.stdin.destroy();if(child.exitCode===null){child.kill();await bounded(closed);}
  const resolved=path.resolve(directory);assert.ok(resolved.startsWith(path.resolve(os.tmpdir())+path.sep)&&path.basename(resolved).startsWith('JentraOS-wave5-peer-early-hold-'));
  await fs.unlink(file);await fs.rmdir(resolved);
 }
});
