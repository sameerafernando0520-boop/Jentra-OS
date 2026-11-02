import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import fs from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const env={...process.env};delete env.SUPABASE_ACCESS_TOKEN;
const run=promisify(execFile),results=[];
for(const name of ['wave5-runtime','wave5-receiver']){
 const directory=fileURLToPath(new URL('download-'+name+'/',import.meta.url));
 await fs.mkdir(directory);
 const startedAt=new Date().toISOString();
 try{
  await run(process.platform==='win32'?'supabase.exe':'supabase',[
   'functions','download',name,'--project-ref','xpdoufauvrbdmxgngetv','--use-api','--workdir',directory],
   {env,encoding:'utf8',timeout:30000,maxBuffer:1048576,windowsHide:true});
  results.push({name,directory,startedAt,finishedAt:new Date().toISOString(),downloaded:true});
 }catch{results.push({name,directory,startedAt,finishedAt:new Date().toISOString(),downloaded:false});}
}
const result={kind:'read-only-current-deployed-worker-download',projectId:'xpdoufauvrbdmxgngetv',
 results,cloudChanged:false,secretValuesRead:false};
await fs.writeFile(new URL('worker-download-result.json',import.meta.url),JSON.stringify(result,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify(result,null,2));
if(results.some(row=>!row.downloaded))process.exitCode=2;
