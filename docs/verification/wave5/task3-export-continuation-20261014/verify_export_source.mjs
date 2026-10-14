import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawn} from 'node:child_process';
const root=process.cwd(),base='docs/verification/wave5/task3-export-continuation-20261014',snapshot='build/wave5-approved-execution-20261013-r5-a2/';
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const read=async file=>{const bytes=await fs.readFile(file);return {path:file,bytes:bytes.length,sha256:sha(bytes)};};
const authored=['tools/wave5/finance_exports_20261014_r5_a5.mjs','tools/wave5/prepare_finance_exports_20261014_r5_a5.mjs',base+'/finance_exports_20261014_r5_a5.test.mjs'];
const plan=JSON.parse(await fs.readFile(snapshot+'docs/verification/wave5/finance-remaining-preparation-20261014-r5-a3.json','utf8'));
const preserved=new Map();for(const binding of [...plan.sourceBindings,...plan.priorEvidenceBindings])preserved.set(snapshot+binding.path,{...binding,path:snapshot+binding.path});
const oldAudit=JSON.parse(await fs.readFile(base+'/source-preservation-manifest.json','utf8'));
for(const binding of oldAudit.sourceBindingsBefore){
 // The live owner explicitly succeeded the shared adapter for A9. Keep that
 // historical input recorded, without calling its old bytes current/preserved.
 if(binding.path==='scripts/wave5/run_private_management_installer_20261013_r5.ps1')continue;
 preserved.set(binding.path,binding);
}
const importFiles=new Set();
async function visit(file){if(importFiles.has(file))return;importFiles.add(file);const source=await fs.readFile(file,'utf8');
 for(const match of source.matchAll(/(?:from\s+|import\s*\(|^\s*import\s+)(['"])([^'"]+)\1/gm)){
  if(match[2].startsWith('node:'))continue;if(!match[2].startsWith('.'))throw Error('UNREVIEWED_EXTERNAL_IMPORT');
  const target=path.relative(root,path.resolve(root,path.dirname(file),match[2])).replaceAll('\\','/');
  if(target.startsWith('../'))throw Error('IMPORT_OUTSIDE_WORKSPACE');await visit(target);
 }
}
for(const file of authored)await visit(file);
const controls=['docs/verification/wave5/task3-completion-20261013/export-continuation-technical-decision-20261014-a2.json',
 'docs/verification/wave5/task3-export-independent-20261014/export-budget-day-independent-review-a3.json',base+'/preliminary-test-failure-a1.json',
 base+'/test-source-before-binding-alias-fix.txt',base+'/budget-feasibility.json',base+'/source-preservation-manifest.json',base+'/verify_export_source.mjs'];
const paths=[...new Set([...importFiles,...preserved.keys(),...controls])].sort();
const before=await Promise.all(paths.map(read));
for(const expected of preserved.values())if(before.find(row=>row.path===expected.path)?.sha256!==expected.sha256)throw Error('PRESERVED_SOURCE_OR_EVIDENCE_DRIFT:'+expected.path);
const env=Object.fromEntries(Object.entries(process.env).filter(([key])=>['SYSTEMROOT','WINDIR','TEMP','TMP'].includes(key.toUpperCase())));
async function run(args){return new Promise(resolve=>{const child=spawn(process.execPath,args,{cwd:root,env,windowsHide:true});let output='',spawnError=false;
 const timer=setTimeout(()=>child.kill(),60000);child.stdout.on('data',chunk=>output+=chunk);child.stderr.on('data',chunk=>output+=chunk);
 child.on('error',()=>spawnError=true);child.on('close',(exitCode,signal)=>{clearTimeout(timer);resolve({args,output,exitCode,signal,spawnError});});});}
const startedAt=new Date().toISOString(),syntax=[];
for(const file of authored)syntax.push(await run(['--check',file]));
const tests=await run(['--test','--test-isolation=none','--test-reporter=tap',authored[2]]);
const after=await Promise.all(paths.map(read)),unchanged=JSON.stringify(before)===JSON.stringify(after);
const count=label=>Number(tests.output.match(new RegExp(`^# ${label} (\\d+)$`,'m'))?.[1]??-1);
const counts=Object.fromEntries(['tests','pass','fail','cancelled','skipped','todo'].map(label=>[label,count(label)]));
const passed=syntax.every(item=>item.exitCode===0&&!item.spawnError)&&tests.exitCode===0&&counts.tests===54&&counts.pass===54
 &&counts.fail===0&&counts.cancelled===0&&counts.skipped===0&&counts.todo===0&&unchanged;
const tapPath=base+'/export-source-final-tests-a3.tap';await fs.writeFile(tapPath,tests.output,{flag:'wx'});
const optionalPublicState={};for(const [name,file] of Object.entries({a10:'docs/verification/wave5/private-owner-input-ready-20261014-r5-a10.json',
 profile:'docs/verification/wave5/task3-completion-20261013/export-continuation-execution-profile-20261014-a1.json',
 finalGate:'docs/verification/wave5/task3-completion-20261013/export-continuation-final-operation-review-20261014-a1.json'})){
 try{optionalPublicState[name]={exists:true,...await read(file)};}catch(error){if(error.code!=='ENOENT')throw error;optionalPublicState[name]={exists:false,path:file};}
}
const result={kind:'controlled-export-successor-source-verification',startedAt,finishedAt:new Date().toISOString(),passed,counts,
 syntax:syntax.map(({output,...record})=>({...record,outputSha256:sha(output),outputBytes:Buffer.byteLength(output)})),
 testCommand:tests.args,testExitCode:tests.exitCode,testSignal:tests.signal,sourcesUnchangedDuringRun:unchanged,
 sourceBindingsBefore:before,sourceBindingsAfter:after,authoredSources:authored.map(file=>before.find(row=>row.path===file)),
 importedSourceFiles:importFiles.size,preservedSourceOrEvidenceFiles:preserved.size,
 originalFinanceSnapshotSourceCount:plan.sourceBindings.length,originalPriorEvidenceCount:plan.priorEvidenceBindings.length,
 oldSharedAdapterHistoricalBinding:oldAudit.sourceBindingsBefore.find(row=>row.path==='scripts/wave5/run_private_management_installer_20261013_r5.ps1'),
 oldSharedAdapterIsNotClaimedCurrent:true,original150SourcesPlansCountersAndIntentsUnchanged:true,
 testTap:{path:tapPath,bytes:Buffer.byteLength(tests.output),sha256:sha(tests.output)},publicExecutionPrerequisiteFiles:optionalPublicState,
 actualCredentialsRead:false,networkCalls:0,privateOrLiveWrites:0,SDKJobs:0,actualExportRegistrations:0,
 scope:'Actual controlled Node suite uses the approved TLS transport with fake socket/server responses, synthetic sessions, bounded disk files and journals. No genuine Auth/database/native/load/release evidence is claimed.',
 conditionalCurrentBudget:{priorAfterRequiredOneActualA10Refresh:132,ordinaryRequests:24,ordinaryCeiling:156,readonlyResolution:1,totalCeiling:157,
 actualA10RefreshByThisVerifier:false,originalAuthorityExpiry:'2026-10-14T09:57:07.481942Z',expiryExtended:false}};
const out=JSON.stringify(result,null,2)+'\n',file=base+'/export-source-local-verification-a3.json';await fs.writeFile(file,out,{flag:'wx'});
process.stdout.write(JSON.stringify({passed,counts,syntaxChecks:syntax.length,sourceBindings:before.length,preserved:preserved.size,
 verification:{path:file,sha256:sha(out)},tap:{path:tapPath,sha256:sha(tests.output)},sources:result.authoredSources})+'\n');
if(!passed)process.exitCode=1;
