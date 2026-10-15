import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {EXPORTS_SOURCE_PATHS,EXPORTS_A5_SOURCE_BINDINGS,EXPORTS_PRESERVED_BINDINGS,EXPORTS_DEPENDENCY,EXPORTS_PROFILE_PATHS,EXPORTS_PROFILE} from '../../../../tools/wave5/finance_exports_20261014_r5_a6.mjs';
const task=fileURLToPath(new URL('./',import.meta.url)),root=fileURLToPath(new URL('../../../../',import.meta.url)),snapshot=path.join(root,'build/wave5-approved-execution-20261013-r5-a2');
const hash=b=>createHash('sha256').update(b).digest('hex');
const must=(v,c)=>{if(!v)throw Error(c);};
const write=async(name,value)=>fs.writeFile(path.join(task,name),JSON.stringify(value,null,2)+'\n',{flag:'wx'});
async function current(){
 const plan=JSON.parse(await fs.readFile(path.join(snapshot,EXPORTS_PRESERVED_BINDINGS.a3Plan.path),'utf8'));must(plan.sourceBindings.length===68,'OLD68_REQUIRED');
 const rows=[],add=async(base,location,expected)=>{const file=path.join(base,location),bytes=await fs.readFile(file),sha256=hash(bytes);
  must(!expected||sha256===expected,'HASH_MISMATCH:'+location);rows.push({root:base===root?'workspace':'frozen',path:location,bytes:bytes.length,sha256});};
 for(const binding of plan.sourceBindings)await add(snapshot,binding.path,binding.sha256);
 for(const binding of Object.values(EXPORTS_PRESERVED_BINDINGS))if(!rows.some(row=>row.root==='frozen'&&row.path===binding.path))await add(snapshot,binding.path,binding.sha256);
 for(const binding of EXPORTS_A5_SOURCE_BINDINGS){await add(root,binding.path,binding.sha256);await add(snapshot,binding.path,binding.sha256);}
 for(const file of EXPORTS_SOURCE_PATHS)await add(root,file);
 await add(root,EXPORTS_DEPENDENCY.path,EXPORTS_DEPENDENCY.sha256);
 const absent=[];
 for(const file of [EXPORTS_PROFILE,...Object.entries(EXPORTS_PROFILE_PATHS).filter(([name])=>name!=='dependency').map(([,file])=>file)]){
  try{await fs.access(path.join(root,file));throw Error('ACTUAL_CONTROL_FILE_ALREADY_EXISTS:'+file);}catch(e){if(e.code!=='ENOENT')throw e;absent.push(file);}
 }
 return {rows,absent};
}
const mode=process.argv[2];
if(mode==='--capture'){
 const values=await current();await write('controlled-source-before-a1.json',{kind:'local-source-only-verification-inputs',capturedAt:new Date().toISOString(),...values});
 process.stdout.write(JSON.stringify({captured:true,bindings:values.rows.length,actualControlsAbsent:values.absent.length})+'\n');
}else if(mode==='--finalize'){
 const before=JSON.parse(await fs.readFile(path.join(task,'controlled-source-before-a1.json'),'utf8')),after=await current();
 must(JSON.stringify(before.rows)===JSON.stringify(after.rows),'SOURCE_CHANGED_DURING_CHECKS');
 const result=JSON.parse(await fs.readFile(path.join(task,'controlled-run-a5.json'),'utf8')),tap=await fs.readFile(path.join(task,'controlled-test-a5.tap'));
 must(result.testExit===0&&result.syntax.length===3&&result.syntax.every(row=>row.exitCode===0),'SYNTAX_OR_TEST_FAILURE');
 must(/# tests 98\r?\n/.test(tap.toString())&&/# pass 98\r?\n/.test(tap.toString())&&/# fail 0\r?\n/.test(tap.toString()),'EXPECTED98_REQUIRED');
 const record={kind:'source-only-export-a6-controlled-verification',passed:true,observedAt:new Date().toISOString(),projectId:'xpdoufauvrbdmxgngetv',
  sources:after.rows.filter(row=>row.root==='workspace'&&EXPORTS_SOURCE_PATHS.includes(row.path)),allBindings:after.rows,
  boundFiles:after.rows.length,original68FrozenBindingsUnchanged:true,a5WorkspaceAndFrozenSourcesUnchanged:true,
  testCount:98,passedTests:98,failedTests:0,syntaxChecks:result.syntax,actualRun:result,
  tap:{path:'docs/verification/wave5/task3-export-renewal-20261014/controlled-test-a5.tap',sha256:hash(tap),bytes:tap.length},
  preservedFailures:[{path:'controlled-test-a1.tap',cause:'Node test process isolation could not spawn: EPERM. No tests ran.'},
   {path:'controlled-test-a2.tap',tests:94,passed:92,failed:2,cause:'Controlled fixtures shared expected and actual binding objects; both mutated together. Fixed fixture cloning; retained failure.'},
   {path:'build_additive_sources.py',cause:'Initial python command resolved unavailable WindowsApps shim; bundled runtime used. No source was written by the failed invocation.'}],
  actualControlFilesAbsent:after.absent,proposedOnlyBudget:{recorded:134,ownerRefresh:1,renewalControl:3,exportPrior:138,ordinary:24,ordinaryLimit:162,resolution:1,total:163},
  actualNetworkCalls:0,actualPrivateReads:0,actualRuntimeRenewals:0,actualA10Refreshes:0,actualExports:0,frozenSnapshotWrites:0,adapterChanges:0,
  approvalCreated:false,requirementsAccepted:0,authenticatedNative:false,productionReady:false};
 await write('export-a6-source-proof-a1.json',record);process.stdout.write(JSON.stringify({passed:true,tests:98,bindings:after.rows.length,sources:record.sources})+'\n');
}else throw Error('MODE_REQUIRED');
