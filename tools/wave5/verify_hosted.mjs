import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash,randomUUID} from 'node:crypto';
import {probeHostedResponses} from './hosted_probe.mjs';

const args=process.argv.slice(2);
if(args.length===1&&args[0]==='--help'){
 process.stdout.write('Usage: node tools/wave5/verify_hosted.mjs\nFour fixed unsigned HTTPS requests. No credentials, model invocation, delivery or retries. New evidence directory per run.\n');
}else{
 if(args.length)throw Error('FIXED_PUBLIC_PROBE_ONLY');
 const workspace=fileURLToPath(new URL('../../',import.meta.url));
 const root=path.join(workspace,'docs','verification','ai-integrations');
 await fs.mkdir(root,{recursive:true});
 const directory=path.join(root,new Date().toISOString().replace(/[:.]/g,'-')+'-'+randomUUID());
 await fs.mkdir(directory);
 const inputs=[];
 for(const name of ['tools/wave5/verify_hosted.mjs','tools/wave5/hosted_probe.mjs',
  'workers/wave5/edge_configuration.mjs','workers/wave5/bounded_json.mjs']){
  const bytes=await fs.readFile(path.join(workspace,name));
  inputs.push({path:name,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')});
 }
 await fs.writeFile(path.join(directory,'source.json'),JSON.stringify({inputs},null,2)+'\n',{flag:'wx'});
 const journal=await fs.open(path.join(directory,'requests.jsonl'),'wx');
 try{
  const report=await probeHostedResponses({record:async row=>{
   await journal.writeFile(JSON.stringify(row)+'\n');await journal.sync();
  }});
  const bytes=JSON.stringify(report,null,2)+'\n';
  await fs.writeFile(path.join(directory,'report.json'),bytes,{flag:'wx'});
  await fs.writeFile(path.join(directory,'report.sha256'),createHash('sha256').update(bytes).digest('hex')+'\n',{flag:'wx'});
  process.stdout.write(JSON.stringify({directory,requests:report.requests,
   unsignedAuthenticationVerified:report.unsignedAuthenticationVerified,
   observations:report.observations.map(({endpoint,status,code,state})=>({endpoint,status,code,state})),
   hostedModelResponseVerified:false,usageAccountingVerified:false,externalDeliveryVerified:false},null,2)+'\n');
  if(!report.unsignedAuthenticationVerified)process.exitCode=2;
 }finally{await journal.close();}
}
