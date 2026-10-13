import fs from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {hashBytes} from './runtime_contract.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url));
let source=await fs.readFile(path.join(root,'tools/wave5/persistent_setup_20261013_r5_a2.mjs'),'utf8');
if(hashBytes(source)!=='8d60a4a779904c7274838200b8ef18626b9e8b1ebd72fec4c978bf2c4fed81f8')throw Error('EXACT_FAILED_A2_SETUP_SOURCE_REQUIRED');
const replace=(before,after)=>{if(source.split(before).length!==2)throw Error('EXACT_SINGLE_SUCCESSOR_REPLACEMENT_REQUIRED');source=source.replace(before,after);};
replace("base+'persistent-setup-20261013-r5-a2-'+Date.now()+'/'", "base+'persistent-setup-20261013-r5-a3-'+Date.now()+'/'");
replace("base+'persistent-setup-once-20261013-r5-a2.json'", "base+'persistent-setup-once-20261013-r5-a3.json'");
replace('declare a intelligence_control.edge_authorities%rowtype;begin','declare a intelligence_control.edge_authorities%rowtype;j bigint;begin');
replace("update cron.job set active=false where jobid=any(a.job_ids) and jobname in (${names.map(n=>`'${n}'`).join(',')});",
 "for j in select jobid from cron.job where jobid=any(a.job_ids) and jobname in (${names.map(n=>`'${n}'`).join(',')}) loop\n perform cron.alter_job(j,active:=false);end loop;");
replace("if(res.statusCode!==200)return fail('FIXED_SETUP_HTTP_FAILURE');",
 "if(res.statusCode!==200){const error=Error('FIXED_SETUP_HTTP_FAILURE');error.publicCode='FIXED_SETUP_HTTP_FAILURE';error.httpStatus=res.statusCode;error.responseSha256=hashBytes(raw);settled=true;clearTimeout(timer);reject(error);return;}");
replace("actualStoppedAt:new Date().toISOString(),automaticRetry:false,mutationMayBeCommitted:true,secretsPrinted:false",
 "actualStoppedAt:new Date().toISOString(),httpStatus:error.httpStatus??null,responseSha256:error.responseSha256??null,automaticRetry:false,mutationMayBeCommitted:true,secretsPrinted:false");
const destination='tools/wave5/persistent_setup_20261013_r5_a3.mjs';const h=await fs.open(path.join(root,destination),'wx');
try{await h.writeFile(source);await h.sync();}finally{await h.close();}
process.stdout.write(JSON.stringify({source:destination,sha256:hashBytes(source),networkCalls:0,previousSourcesPreserved:true,
 change:'Pause only the exact three newly created reviewed jobs through executable cron.alter_job; direct cron.job UPDATE removed.'})+'\n');
