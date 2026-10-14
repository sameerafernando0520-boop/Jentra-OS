import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../../../../',import.meta.url));
const output='docs/verification/wave5/task3-v7-provider-20261014/';
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const predecessorSources=[
 {role:'persistent_control',path:'workers/wave5/persistent_control.mjs',sha256:'81b5aa332971235cca8830c3d5894977d04baa5d0f3b6f1391db346ca9abc4fd'},
 {role:'scoped_runtime',path:'workers/wave5/scoped_runtime.mjs',sha256:'70a8edbb7e8a0bac3fa1856ebb1134ff14413ad5b81f63bc568ae7750d3b2489'},
 {role:'edge_runtime',path:'workers/wave5/edge_runtime_20261014_r5_v6.mjs',sha256:'b5be66b51e3f3c46050bbeda8dcab930dc4ed80d102fc2959360ef3487a54776'},
 {role:'edge_receiver',path:'workers/wave5/edge_receiver_20261014_r5_v6.mjs',sha256:'e4a0df9a150b7524762ba8d6ea13c5c4e24c5fe6abe2d27fafdb6bb5ffa1f948'},
];
const written=[],predecessors=[];
async function create(file,source){const bytes=Buffer.from(source);const handle=await fs.open(path.join(root,file),'wx');
 try{await handle.writeFile(bytes);await handle.sync();}finally{await handle.close();}
 written.push({path:file,bytes:bytes.length,sha256:hash(bytes)});
}
const helper=`// Privileged worker credentials only. Format validation never decodes a key
// or grants caller access. Only the existing server-supplied key is accepted.
export function serviceCredentialKind(value){
 if(typeof value!=='string'||value.length<32)return null;
 if(/^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$/.test(value))return 'legacy_jwt';
 if(/^sb_secret_[A-Za-z0-9_-]+$/.test(value))return 'opaque_secret';
 return null;
}

// Opaque Supabase secret keys are API keys, not Bearer JWTs. Legacy service
// JWTs retain both headers. Never expose these headers in logs or responses.
export function serviceProviderHeaders(serviceKey){
 const kind=serviceCredentialKind(serviceKey);
 if(kind===null)throw Error('WORKER_CONFIGURATION_INVALID');
 return Object.freeze(kind==='legacy_jwt'
  ?{apikey:serviceKey,authorization:\`Bearer \${serviceKey}\`}
  :{apikey:serviceKey});
}
`;
await create('workers/wave5/provider_credentials_20261014_r5_v7.mjs',helper);
for(const binding of predecessorSources){
 const bytes=await fs.readFile(path.join(root,binding.path));assert.equal(hash(bytes),binding.sha256);
 predecessors.push({...binding,bytes:bytes.length});let source=bytes.toString('utf8');
 const replace=(old,value)=>{assert.equal(source.split(old).length,2,'exact candidate replacement required');source=source.replace(old,value);};
 if(binding.role==='persistent_control'){
  source="import {serviceProviderHeaders} from './provider_credentials_20261014_r5_v7.mjs';\n"+source;
  replace(" return async(name,params)=>{"," const providerHeaders=serviceProviderHeaders(serviceKey);\n return async(name,params)=>{");
  replace("headers:{'apikey':serviceKey,'authorization':`Bearer ${serviceKey}`,'content-profile':'api','accept-profile':'api','content-type':'application/json'},",
   "headers:{...providerHeaders,'content-profile':'api','accept-profile':'api','content-type':'application/json'},");
 }else if(binding.role==='scoped_runtime')replace("from './persistent_control.mjs'","from './persistent_control_20261014_r5_v7.mjs'");
 else{
  source="import {serviceCredentialKind} from './provider_credentials_20261014_r5_v7.mjs';\n"+source;
  replace("from './persistent_control.mjs'","from './persistent_control_20261014_r5_v7.mjs'");
  if(binding.role==='edge_runtime'){
   replace("from './scoped_runtime.mjs'","from './scoped_runtime_20261014_r5_v7.mjs'");
   replace("if(!/^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$/.test(serviceKey))throw Error('WORKER_PROVIDER_UNAVAILABLE');",
    "if(serviceCredentialKind(serviceKey)===null)throw Error('WORKER_PROVIDER_UNAVAILABLE');");
  }else replace("if(!/^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$/.test(serviceKey??''))throw Error('WORKER_PROVIDER_UNAVAILABLE');",
   "if(serviceCredentialKind(serviceKey)===null)throw Error('WORKER_PROVIDER_UNAVAILABLE');");
 }
 await create(`workers/wave5/${binding.role}_20261014_r5_v7.mjs`,source);
}
await fs.mkdir(path.join(root,'workers/wave5/entries'),{recursive:true});
for(const worker of ['runtime','receiver']){
 const factory=worker==='runtime'?'Runtime':'Receiver';
 await create(`workers/wave5/entries/${worker}_20261014_r5_v7.ts`,
  `import {createEdge${factory}} from '../edge_${worker}_20261014_r5_v7.mjs';\n`
  +"import {withBoundedProviderDiagnostic} from '../edge_route_20261014_r5_v6.mjs';\n"
  +"import {edgeConfiguration} from '../edge_configuration.mjs';\n\n"
  +'// Caller authentication stays in the reviewed handler. The V6 diagnostic\n'
  +'// still emits only its single finite configuration-shape observation.\n'
  +'Deno.serve(withBoundedProviderDiagnostic({\n'
  +` handler:createEdge${factory}({env:Deno.env}),env:Deno.env,\n`
  +` configuredUrl:edgeConfiguration.url,worker:'${worker}',\n`
  +' observe:(classification:unknown)=>console.info(JSON.stringify(classification)),\n}));\n');
}
for(const binding of predecessors)assert.equal(hash(await fs.readFile(path.join(root,binding.path))),binding.sha256);
const record={kind:'additive-worker-v7-provider-credential-candidate-preparation',preparedAt:new Date().toISOString(),
 projectId:'xpdoufauvrbdmxgngetv',author:'/root/completion_peer',predecessors,written:[...written],
 privilegedOpaqueCredentialHeader:'apikey_only',privilegedLegacyCredentialHeaders:['apikey','authorization'],
 originalCallerJwtModelReaderUnchanged:true,sourceFilesCreated:7,existingSourcesOverwritten:0,
 privateInputsRead:0,environmentWrites:0,networkRequests:0,liveSql:0,deployments:0,schedulesChanged:0,sdkJobs:0,
 independentReviewPending:true,personalHumanExactSourceSignatureClaimed:false};
const name=output+'source-preparation.json';await create(name,JSON.stringify(record,null,2)+'\n');
console.log(JSON.stringify({prepared:true,sourcePreparation:name,sources:record.written}));
