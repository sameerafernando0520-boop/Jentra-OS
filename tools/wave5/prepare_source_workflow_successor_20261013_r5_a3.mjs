import fs from 'node:fs/promises';
import {hashBytes} from './runtime_contract.mjs';
const old='tools/wave5/resume_source_workflows_20261013_r5.mjs';
let source=await fs.readFile(old,'utf8');
if(hashBytes(source)!=='9058710e0468e3b44dee99ae1a6c3c8a414146a50e5b3060df3094030d912200')throw Error('PRESERVED_RESUME_SOURCE_CHANGED');
const replace=(before,after)=>{if(source.split(before).length!==2)throw Error('EXACT_SUCCESSOR_EDIT_REQUIRED');source=source.replace(before,after);};
replace("const must=(v,code)=>", "const additional=base+'genuine-source-workflows-resumed-20261013-r5-1791882899175/';\nconst must=(v,code)=>");
replace("const directory=base+'genuine-source-workflows-resumed-20261013-r5-'", "const directory=base+'genuine-source-workflows-completed-20261013-r5-a3-'");
replace("source-workflows-resume-once-20261013-r5.json", "source-workflows-resume-once-20261013-r5-a3.json");
replace("maximumNewCommands:496", "maximumNewCommands:491");
replace("existingForecastsPreserved:4", "existingForecastsPreserved:9");
replace("newCommands===496", "newCommands===491");
replace("existingForecastIdentitiesPreserved:4,newForecastCommands:496", "existingForecastIdentitiesPreserved:9,newForecastCommands:491");
replace("let originalIntent,forecastId,originalResponse;", "let originalIntent,forecastId,originalResponse,originalEvidenceDirectory=prior;");
replace("catch(e){if(e.code!=='ENOENT')throw e;}\n   if(originalIntent)", "catch(e){if(e.code!=='ENOENT')throw e;}\n   if(!originalIntent){try{originalIntent=JSON.parse(await fs.readFile(path.join(root,additional+scope.key+'-intent.json'),'utf8'));originalEvidenceDirectory=additional;}catch(e){if(e.code!=='ENOENT')throw e;}}\n   if(originalIntent)");
replace("path.join(root,prior+scope.key+'-result.json')", "path.join(root,originalEvidenceDirectory+scope.key+'-result.json')");
replace("['runtime','foreign','load-001','load-002'].includes(scope.key)", "['runtime','foreign','load-001','load-002','load-003','load-004','load-005','load-006','load-007'].includes(scope.key)");
replace("denied.value?.message==='PERMISSION_DENIED'", "denied.status===403&&denied.value?.code==='42501'&&denied.value?.message==='Permission denied or multi-factor authentication required.'");
replace("const now=Date.parse(nowResult.value[0].observed_at)", `const known=[];
  for(const target of review.syntheticScopes){let intent,where=prior;try{intent=JSON.parse(await fs.readFile(path.join(root,prior+target.key+'-intent.json'),'utf8'));}catch(e){if(e.code!=='ENOENT')throw e;}
   if(!intent){try{intent=JSON.parse(await fs.readFile(path.join(root,additional+target.key+'-intent.json'),'utf8'));where=additional;}catch(e){if(e.code!=='ENOENT')throw e;}}
   if(intent){const record=target.key==='runtime'?{forecast:{id:recovery.originalCommand.result.entity.id,sourceHash:recovery.originalCommand.result.entity.sourceHash}}:JSON.parse(await fs.readFile(path.join(root,where+target.key+'-result.json'),'utf8'));
    known.push({tenant_id:target.tenantId,id:record.forecast.id,source_hash:record.forecast.sourceHash,command_id:intent.commandId});}}
  must(known.length===9&&known.every(k=>isUuid(k.id)&&isUuid(k.command_id)),'EXACT_NINE_RECORDED_OUTCOMES_REQUIRED');
  const tenants=review.syntheticScopes.map(s=>"'"+s.tenantId+"'::uuid").join(',');calls++;
  const observed=await management('POST','/database/query',{query:'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY; SELECT f.tenant_id,f.id,f.source_hash,r.command_id FROM analytics.pipeline_forecasts f JOIN core.command_receipts r ON r.tenant_id=f.tenant_id AND r.aggregate_id=f.id WHERE f.tenant_id IN('+tenants+');ROLLBACK;',read_only:true});
  must(observed.value.length===9&&known.every(k=>observed.value.some(o=>o.tenant_id===k.tenant_id&&o.id===k.id&&o.source_hash===k.source_hash&&o.command_id===k.command_id)),'FRESH_NINE_ORIGINAL_IDENTITIES_REQUIRED');
  await save(directory+'00-nine-original-identities.json',{actualReturnedRows:observed.value,responseSha256:observed.responseSha256,existingIdentitiesPreserved:true});
  const now=Date.parse(nowResult.value[0].observed_at)`);
const output='tools/wave5/continue_source_workflows_20261013_r5_a3.mjs';
const handle=await fs.open(output,'wx');try{await handle.writeFile(source);await handle.sync();}finally{await handle.close();}
process.stdout.write(JSON.stringify({successorPrepared:true,path:output,sha256:hashBytes(source),originalSourcePreserved:true,networkCalls:0})+'\n');
