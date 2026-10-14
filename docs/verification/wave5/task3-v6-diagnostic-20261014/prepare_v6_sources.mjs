import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
const root=process.cwd();
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');
const appendix=`
// Provider configuration classification only. No key/URL is parsed or emitted.
// Module scope bounds every entrypoint in this isolate to one attempted sample.
let providerDiagnosticRemaining=1;
const providerUrlClasses=Object.freeze(['exact_configured_https','exact_configured_https_with_slash','exact_project_http','missing','other']);
const serviceRoleShapes=Object.freeze(['legacy_jwt','opaque_secret_style','missing','other']);
function providerEnvValue(env,name){return typeof env.get==='function'?env.get(name):env[name];}
export function classifyProviderEnvironment(env,configuredUrl){
 if(configuredUrl!==projectOrigin)throw Error('PROVIDER_DIAGNOSTIC_CONFIGURATION_INVALID');
 const url=providerEnvValue(env,'SUPABASE_URL'),serviceRole=providerEnvValue(env,'SUPABASE_SERVICE_ROLE_KEY');
 const dictionary=providerEnvValue(env,'SUPABASE_SECRET_KEYS');
 const supabaseUrlClass=url===configuredUrl?'exact_configured_https'
  :url===configuredUrl+'/'?'exact_configured_https_with_slash'
  :url===projectHttpOrigin?'exact_project_http'
  :url===undefined||url===null||url===''?'missing':'other';
 const serviceRoleShape=typeof serviceRole==='string'&&/^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$/.test(serviceRole)?'legacy_jwt'
  :typeof serviceRole==='string'&&/^sb_secret_[A-Za-z0-9_-]+$/.test(serviceRole)?'opaque_secret_style'
  :serviceRole===undefined||serviceRole===null||serviceRole===''?'missing':'other';
 if(!providerUrlClasses.includes(supabaseUrlClass)||!serviceRoleShapes.includes(serviceRoleShape))throw Error('PROVIDER_DIAGNOSTIC_CLASS_INVALID');
 return Object.freeze({supabaseUrlClass,serviceRoleShape,secretKeysDictionaryPresent:typeof dictionary==='string'&&dictionary.length>0});
}

// The original handler runs first. Diagnostic reads/throws/rejected sinks do
// not replace, await or change its response or error. No request field is read.
export function withBoundedProviderDiagnostic({handler,env,configuredUrl,worker,observe}){
 if(typeof handler!=='function'||typeof observe!=='function'||configuredUrl!==projectOrigin
  ||!['runtime','receiver'].includes(worker))throw Error('PROVIDER_DIAGNOSTIC_CONFIGURATION_INVALID');
 return req=>{
  const sample=providerDiagnosticRemaining>0;
  if(sample)providerDiagnosticRemaining--;
  const diagnose=()=>{
   if(!sample)return;
   try{
    const descriptor=Object.freeze({kind:'wave5_provider_v6',worker,...classifyProviderEnvironment(env,configuredUrl)});
    const pending=observe(descriptor);
    if(pending&&typeof pending.catch==='function')pending.catch(()=>{});
   }catch{}
  };
  try{
   const output=handler(req);
   if(output&&typeof output.then==='function')return output.then(response=>{diagnose();return response;},error=>{diagnose();throw error;});
   diagnose();return output;
  }catch(error){diagnose();throw error;}
 };
}
`;
const written=[];
for(const role of ['route','runtime','receiver']){
 const predecessor=`workers/wave5/edge_${role}_20261014_r5_v5.mjs`,target=`workers/wave5/edge_${role}_20261014_r5_v6.mjs`;
 const original=await fs.readFile(path.join(root,predecessor));
 const bytes=role==='route'?Buffer.concat([original,Buffer.from(appendix)])
  :Buffer.from(original.toString('utf8').replace('./edge_route_20261014_r5_v5.mjs','./edge_route_20261014_r5_v6.mjs'));
 await fs.writeFile(path.join(root,target),bytes,{flag:'wx'});
 written.push({path:target,bytes:bytes.length,sha256:sha(bytes),predecessor:{path:predecessor,bytes:original.length,sha256:sha(original)}});
}
for(const worker of ['runtime','receiver']){
 const source=`import {createEdge${worker==='runtime'?'Runtime':'Receiver'}} from '../../../workers/wave5/edge_${worker}_20261014_r5_v6.mjs';
import {withBoundedProviderDiagnostic} from '../../../workers/wave5/edge_route_20261014_r5_v6.mjs';
import {edgeConfiguration} from '../../../workers/wave5/edge_configuration.mjs';

// The unchanged handler authenticates before this single finite observation.
// Provider keys and URL values never reach the diagnostic sink.
Deno.serve(withBoundedProviderDiagnostic({
 handler:createEdge${worker==='runtime'?'Runtime':'Receiver'}({env:Deno.env}),env:Deno.env,
 configuredUrl:edgeConfiguration.url,worker:'${worker}',
 observe:(classification:unknown)=>console.info(JSON.stringify(classification)),
}));
`;
 const target=`supabase/functions/wave5-${worker}/index_20261014_r5_v6.ts`,bytes=Buffer.from(source);
 await fs.writeFile(path.join(root,target),bytes,{flag:'wx'});written.push({path:target,bytes:bytes.length,sha256:sha(bytes)});
}
const record={kind:'additive-worker-v6-provider-diagnostic-source-preparation',preparedAt:new Date().toISOString(),written,
  sharedSourceOverwritten:false,networkCalls:0,environmentWrites:0,privateInputsRead:false,deployments:0,schedulesChanged:0,SDKJobs:0};
const output='docs/verification/wave5/task3-v6-diagnostic-20261014/source-preparation.json';
await fs.writeFile(path.join(root,output),JSON.stringify(record,null,2)+'\n',{flag:'wx'});
process.stdout.write(JSON.stringify({record:output,files:written.map(file=>({path:file.path,sha256:file.sha256}))})+'\n');
