import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {readFile,writeFile,mkdir,readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';

const root=process.cwd(),project='xpdoufauvrbdmxgngetv';
const base=path.join(root,'docs/verification/ai-integrations-test-20261103');
const directory=path.join(root,'build/wave5-external-delivery-review-20261103/receiver-readback');
const env={...process.env};delete env.SUPABASE_ACCESS_TOKEN;
const hash=b=>createHash('sha256').update(b).digest('hex');
const cli=async args=>promisify(execFile)('C:\\Users\\sheha\\scoop\\shims\\supabase.exe',args,{cwd:directory,env,windowsHide:true,encoding:'utf8',timeout:120000,maxBuffer:4194304});
const metadata=f=>Object.fromEntries(['id','slug','status','version','updated_at','verify_jwt','entrypoint_path','ezbr_sha256'].map(k=>[k,f[k]]));
try{
 await mkdir(path.join(directory,'supabase'),{recursive:true});
 await writeFile(path.join(directory,'supabase/config.toml'),'project_id = "jentra-receiver-readonly-review"\n',{flag:'wx'});
 const list=JSON.parse((await cli(['functions','list','--project-ref',project,'--output','json'])).stdout);
 const receiver=list.find(x=>x.slug==='wave5-receiver');
 if(receiver?.status!=='ACTIVE')throw Error('ACTIVE_RECEIVER_REQUIRED');
 await cli(['functions','download','wave5-receiver','--project-ref',project,'--use-api','--output','json']);
 const files=[];
 const walk=async d=>{for(const item of await readdir(d,{withFileTypes:true})){
  if(item.isSymbolicLink())throw Error('SOURCE_SYMLINK');
  const absolute=path.join(d,item.name);
  if(item.isDirectory())await walk(absolute);else if(item.isFile()&&/\.(?:mjs|ts)$/.test(item.name)){
   const bytes=await readFile(absolute);if(bytes.length>1048576||files.length>64)throw Error('SOURCE_LIMIT');
   const local=item.name==='receiver_20261014_r5_v7.ts'?path.join(root,'workers/wave5/entries',item.name):path.join(root,'workers/wave5',item.name);
   let localHash=null;try{localHash=hash(await readFile(local));}catch{}
   files.push({path:path.relative(directory,absolute).replaceAll('\\','/'),sha256:hash(bytes),localMatch:localHash===hash(bytes)});
  }
 }};await walk(directory);
 const after=JSON.parse((await cli(['functions','list','--project-ref',project,'--output','json'])).stdout).find(x=>x.slug==='wave5-receiver');
 const unchanged=JSON.stringify(metadata(receiver))===JSON.stringify(metadata(after));
 const result={projectId:project,observedAt:new Date().toISOString(),readOnly:true,receiver:metadata(after),metadataUnchangedDuringRead:unchanged,files,allModulesMatchLocal:files.length>0&&files.every(f=>f.localMatch),readbackDirectory:directory,databaseChanged:false,deliverySent:false,secretsReadOrPrinted:false};
 await writeFile(path.join(base,'external-receiver-readback.json'),JSON.stringify(result,null,2)+'\n',{flag:'wx'});
 console.log(JSON.stringify({receiverVersion:after.version,modules:files.length,allModulesMatchLocal:result.allModulesMatchLocal,metadataUnchangedDuringRead:unchanged,deliverySent:false}));
 if(!unchanged||!result.allModulesMatchLocal)process.exitCode=1;
}catch(e){console.error(JSON.stringify({code:/^[A-Z0-9_]+$/.test(e.message)?e.message:'READ_ONLY_RECEIVER_CHECK_FAILED',deliverySent:false,secretsPrinted:false}));process.exitCode=1;}
