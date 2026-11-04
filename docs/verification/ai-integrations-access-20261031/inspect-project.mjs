// Fixed-project, read-only metadata. The CLI owns its saved credential; no token
// value is read or printed. The stale environment override is omitted per child.
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {writeFile} from 'node:fs/promises';
const run=promisify(execFile),project='xpdoufauvrbdmxgngetv';
const env={...process.env};delete env.SUPABASE_ACCESS_TOKEN;
async function cli(args){
 try{
  const {stdout}=await run(process.platform==='win32'?'supabase.exe':'supabase',args,
   {env,encoding:'utf8',timeout:20000,maxBuffer:1048576,windowsHide:true});
  return JSON.parse(stdout);
 }catch{throw Error('HOSTED_METADATA_READ_UNCONFIRMED');}
}
const projects=await cli(['projects','list','--output','json']);
if(!Array.isArray(projects))throw Error('PROJECT_LIST_INVALID');
const matches=projects.filter(row=>row.ref===project||row.id===project);
if(matches.length!==1||matches[0].status!=='ACTIVE_HEALTHY')throw Error('EXACT_HEALTHY_PROJECT_REQUIRED');
const [functions,secrets]=await Promise.all([
 cli(['functions','list','--project-ref',project,'--output','json']),
 cli(['secrets','list','--project-ref',project,'--output','json'])]);
if(!Array.isArray(functions)||!Array.isArray(secrets))throw Error('HOSTED_METADATA_SHAPE_INVALID');
const result={kind:'current-jentra-hosted-metadata',observedAt:new Date().toISOString(),projectId:project,
 projectName:matches[0].name,status:matches[0].status,region:matches[0].region,
 savedCliAuthenticationVerified:true,staleEnvironmentOverrideOmitted:true,
 functions:functions.map(row=>({id:row.id,slug:row.slug,name:row.name,status:row.status,version:row.version,
  verifyJwt:row.verify_jwt,updatedAt:row.updated_at,entrypointPath:row.entrypoint_path})),
 modelSecretPresent:secrets.some(row=>row.name==='W5_OPENAI_API_KEY'),
 modelRelatedSecretNames:secrets.filter(row=>typeof row.name==='string'&&/OPENAI|MODEL|W5/i.test(row.name)).map(row=>row.name),
 secretValuesRead:false,secretValuesPrinted:false,configurationChanged:false,
 boundary:'Current CLI project/function metadata and secret-name presence only; no deployed source readback, database query, provider call or delivery.'};
await writeFile(new URL('hosted-project-metadata.json',import.meta.url),JSON.stringify(result,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify(result,null,2));
