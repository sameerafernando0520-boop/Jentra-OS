// Controlled public fixtures only. The actual private adapters are never run.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {createInterface} from 'node:readline';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {buildCandidate,PREDECESSOR,LOCK_SOURCE} from '../../../../tools/wave5/prepare_export_private_adapter_20261016_r5_a2.mjs';
import {buildManagementCandidate,TEMPLATE} from '../../../../tools/wave5/prepare_management_private_adapter_20261016_r5_a2.mjs';
const root=fileURLToPath(new URL('../../../../',import.meta.url));
const pwsh='C:/Users/sheha/.cache/codex-runtimes/codex-primary-runtime/dependencies/native/powershell/pwsh.exe';
const [before,locks,template]=await Promise.all([fs.readFile(path.join(root,PREDECESSOR.path)),fs.readFile(path.join(root,LOCK_SOURCE),'utf8'),fs.readFile(path.join(root,TEMPLATE.path))]);
const hash=x=>createHash('sha256').update(x).digest('hex');
const fixtureHash='f'.repeat(64);
const exportText=buildCandidate(before,fixtureHash,locks).text;
const managementText=buildManagementCandidate(template,locks,{Renewal:fixtureHash,Health:'e'.repeat(64),Scheduler:'d'.repeat(64),OwnerRefresh:'c'.repeat(64)});
const denied=error=>['EPERM','EACCES','EBUSY'].includes(error?.code);
const deadline=(label,ms=15000)=>new Promise((_,reject)=>{const timer=setTimeout(()=>reject(Error(label)),ms);timer.unref();});
function runPs(script){
 const child=spawn(pwsh,['-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',Buffer.from(script,'utf16le').toString('base64')],{windowsHide:true,stdio:['pipe','pipe','pipe']});
 let stdout='',stderr='';child.stdout.on('data',x=>{stdout+=x;});child.stderr.on('data',x=>{stderr+=x;});
 const closed=once(child,'close');
 return {child,async finish(input){child.stdin.end(input);const [code]=await Promise.race([closed,deadline('CONTROLLED_POWERSHELL_TIMEOUT')]);assert.equal(stderr,'');return {code,stdout};}};
}
test('both adapter builders retain exact original templates and embed the reviewed lock implementation',()=>{
 assert.equal(hash(before),PREDECESSOR.sha256);assert.equal(hash(template),TEMPLATE.sha256);
 assert.ok(exportText.includes(locks));assert.ok(managementText.includes(locks));
 assert.throws(()=>buildCandidate(Buffer.concat([before,Buffer.from('\n')]),fixtureHash,locks),/EXACT_PRESERVED_PRIVATE_ADAPTER_REQUIRED/);
 assert.throws(()=>buildManagementCandidate(Buffer.concat([template,Buffer.from('\n')]),locks,{Renewal:fixtureHash}),/EXACT_PRESERVED_MANAGEMENT_TEMPLATE_REQUIRED/);
});
test('export adapter locks source/public inventories, exact plan, review, manifest and self before public preflight',()=>{
 const hold=exportText.indexOf('foreach ($taskBinding in @($taskExportPlan.sourceBindings))'),preflight=exportText.indexOf("$taskPhase = 'public-export-preflight'");
 assert.ok(hold>0&&hold<preflight);
 for(const token of ['@($taskExportPlan.publicBindings)','Add-TaskReviewedReadHold $taskExecutionRoot','Add-TaskReviewedReadHold $taskRoot $taskSelfRelative',
  "finance-exports-preparation-20261016-r5-a7.json","task3-export-renewal-20261016/final-operation-review-a1.json"])
  assert.ok(exportText.slice(hold,preflight).includes(token),token);
 const guard=exportText.slice(exportText.indexOf("throw 'PRIVATE_METADATA_CHANGED'"),exportText.indexOf('$taskSecret = ConvertTo-SecureString -String'));
 assert.ok(guard.includes('Get-FileHash -LiteralPath $taskInstaller'));assert.ok(guard.includes('Get-FileHash -LiteralPath $taskExportPlanPath'));
 assert.ok(!exportText.includes('ExportsA6'));assert.ok(exportText.includes("if ($Mode -eq 'ValidateExportsA7')"));
});
test('management adapter holds complete public inventory before any child or private read',()=>{
 const hold=managementText.indexOf('foreach ($taskBinding in @($taskPlan.sourceBindings) + @($taskPlan.publicBindings))');
 assert.ok(hold>0&&hold<managementText.indexOf("$taskChild = New-TaskProcess '--preflight'"));
 for(const token of ['Add-TaskReviewedReadHold $taskRoot $taskSelected.source','Add-TaskReviewedReadHold $taskRoot $taskSelected.plan',
  'Add-TaskReviewedReadHold $taskRoot $taskSelected.review','Add-TaskReviewedReadHold $taskRoot $taskMetadataPath',
  'Add-TaskReviewedReadHold $taskRoot $taskSelfRelative'])assert.ok(managementText.includes(token),token);
 assert.ok(managementText.indexOf("if ($Action -eq 'Validate')")<managementText.indexOf('[Security.Principal.WindowsIdentity]::GetCurrent()'));
 assert.ok(managementText.includes('} finally { Close-TaskReviewedReadHolds }'));
 assert.ok(!managementText.includes('__OWNER_REFRESH_SOURCE_SHA256__'));
});
test('PowerShell parser accepts both generated adapters without executing either',async()=>{
 const config=Buffer.from(JSON.stringify([exportText,managementText])).toString('base64');
 // Text travels over stdin, avoiding command-line length limits and shell interpolation.
 const script="$ErrorActionPreference='Stop'; $taskTexts=[Console]::In.ReadToEnd()|ConvertFrom-Json; $taskCount=0; foreach($taskText in $taskTexts){ $taskTokens=$null; $taskErrors=$null; $null=[Management.Automation.Language.Parser]::ParseInput($taskText,[ref]$taskTokens,[ref]$taskErrors); if($taskErrors.Count -ne 0){throw 'CONTROLLED_AST_PARSE_FAILED'}; $taskCount++ }; [Console]::Out.WriteLine((@{parsed=$taskCount;executed=$false}|ConvertTo-Json -Compress))";
 const result=await runPs(script).finish(Buffer.from(config,'base64').toString('utf8'));assert.equal(result.code,0);assert.deepEqual(JSON.parse(result.stdout),{parsed:2,executed:false});
});
async function fixture(){
 const directory=await fs.mkdtemp(path.join(root,'build','wave5-public-adapter-control-'));
 const files=[{name:'source.mjs',bytes:Buffer.from('export const fixtureValue = 42;\n')},{name:'plan.json',bytes:Buffer.from('{"fixture":true}\n')}];
 for(const row of files){row.file=path.join(directory,row.name);row.sha256=hash(row.bytes);await fs.writeFile(row.file,row.bytes,{flag:'wx'});}
 return {directory,files,async clean(){assert.ok(path.resolve(directory).startsWith(path.join(root,'build')+path.sep)&&path.basename(directory).startsWith('wave5-public-adapter-control-'));for(const row of files)await fs.unlink(row.file).catch(e=>{if(e.code!=='ENOENT')throw e;});for(const name of ['replacement.tmp','renamed.tmp'])await fs.unlink(path.join(directory,name)).catch(e=>{if(e.code!=='ENOENT')throw e;});await fs.rmdir(directory);}};
}
function holdFixture(f,{badSecond=false,duplicateCollision=false}={}){
 const rows=f.files.map((row,i)=>({path:row.name,sha256:badSecond&&i===1?'0'.repeat(64):row.sha256}));
 if(duplicateCollision)rows.push({path:rows[0].path,sha256:'0'.repeat(64)});
 const config=Buffer.from(JSON.stringify({base:f.directory,rows})).toString('base64');
 const script=`$ErrorActionPreference='Stop'
${locks}
$taskFixture=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${config}'))|ConvertFrom-Json
try {
 foreach($taskRow in $taskFixture.rows){ Add-TaskReviewedReadHold $taskFixture.base $taskRow.path $taskRow.sha256 }
 [Console]::Out.WriteLine('{"held":true}');[Console]::Out.Flush()
 $taskReply=[Console]::In.ReadLine()
 if($taskReply -eq 'fail'){throw 'CONTROLLED_AFTER_HOLD_FAILURE'}
 if($taskReply -ne 'release'){throw 'CONTROLLED_RELEASE_REQUIRED'}
 exit 0
} catch {
 [Console]::Out.WriteLine((@{failureCode=$_.Exception.Message}|ConvertTo-Json -Compress)); exit 1
} finally { Close-TaskReviewedReadHolds }
`;
 const p=runPs(script),lines=createInterface({input:p.child.stdout});
 const first=Promise.race([once(lines,'line').then(([line])=>JSON.parse(line)),deadline('CONTROLLED_HOLD_READY_TIMEOUT')]);
 return {...p,first,stop(){lines.close();p.child.stdin.destroy();if(p.child.exitCode===null)p.child.kill();}};
}
for(const signal of ['release','fail'])test(`actual embedded lock functions prevent replacement and release handles after ${signal}`,async()=>{
 const f=await fixture(),held=holdFixture(f);
 try{
  assert.deepEqual(await held.first,{held:true});
  for(const row of f.files){assert.equal(hash(await fs.readFile(row.file)),row.sha256);await assert.rejects(fs.writeFile(row.file,'mutation'),denied);await assert.rejects(fs.unlink(row.file),denied);}
  await assert.rejects(fs.rename(f.files[0].file,path.join(f.directory,'renamed.tmp')),denied);
  const replacement=path.join(f.directory,'replacement.tmp');await fs.writeFile(replacement,'replacement',{flag:'wx'});await assert.rejects(fs.rename(replacement,f.files[0].file),denied);
  const result=await held.finish(signal+'\n');assert.equal(result.code,signal==='release'?0:1);
  for(const row of f.files)await fs.writeFile(row.file,'released');
 }finally{held.stop();await f.clean();}
});
for(const options of [{badSecond:true},{duplicateCollision:true}])test(`partial actual lock acquisition releases handles on ${Object.keys(options)[0]}`,async()=>{
 const f=await fixture(),held=holdFixture(f,options);
 try{
  const first=await held.first;assert.equal(first.failureCode,options.badSecond?'REVIEWED_FILE_HASH_CHANGED':'REVIEWED_FILE_HASH_COLLISION');
  assert.equal((await held.finish()).code,1);for(const row of f.files)await fs.writeFile(row.file,'released');
 }finally{held.stop();await f.clean();}
});
