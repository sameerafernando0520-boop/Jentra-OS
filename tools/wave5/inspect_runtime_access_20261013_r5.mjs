import fs from 'node:fs/promises';
import path from 'node:path';
import https from 'node:https';
import { fileURLToPath } from 'node:url';
import { PROJECT,BUNDLE,loadApprovedInputs } from './approved_management_installer.mjs';
import { hashBytes } from './runtime_contract.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),base='docs/verification/wave5/';
const routes=Object.freeze({temporaryAccess:'/jit-access',userRoleMapping:'/database/jit',tlsEnforcement:'/ssl-enforcement',
 pooler:'/config/database/pooler',secretNames:'/secrets'});
const must=(ok,code)=>{if(!ok){const error=Error(code);error.publicCode=code;throw error;}};
function readOnly(ownerToken,suffix){must(Object.values(routes).includes(suffix),'EXACT_READ_ONLY_RUNTIME_METADATA_REQUIRED');
 return new Promise((resolve,reject)=>{let req,timer,settled=false,size=0;const chunks=[];
  const fail=code=>{if(settled)return;settled=true;clearTimeout(timer);req?.destroy();const error=Error(code);error.publicCode=code;reject(error);};
  try{req=https.request(`https://api.supabase.com/v1/projects/${PROJECT}${suffix}`,{method:'GET',rejectUnauthorized:true,
   headers:{Authorization:`Bearer ${ownerToken}`}},res=>{
    res.on('error',()=>fail('RUNTIME_ACCESS_READ_UNCERTAIN'));res.on('data',chunk=>{if(settled)return;size+=chunk.length;
     if(size>1024*1024)fail('RUNTIME_ACCESS_METADATA_LIMIT');else chunks.push(chunk);});
    res.on('end',()=>{if(settled)return;const raw=Buffer.concat(chunks);let value;
     if(res.statusCode!==200){fail('RUNTIME_ACCESS_READ_DENIED');return;}
     try{value=JSON.parse(raw);}catch{fail('RUNTIME_ACCESS_METADATA_INVALID');return;}
     settled=true;clearTimeout(timer);resolve({value,responseSha256:hashBytes(raw),actualFinishedAt:new Date().toISOString()});});});
   req.on('error',()=>fail('RUNTIME_ACCESS_TRANSPORT_UNCERTAIN'));timer=setTimeout(()=>fail('RUNTIME_ACCESS_TIMEOUT'),45000);
   req.once('socket',socket=>{const send=()=>{if(settled){req.destroy();return;}if(socket.encrypted!==true||socket.authorized!==true){fail('VERIFIED_METADATA_TLS_REQUIRED');return;}req.end();};
    if(settled){req.destroy();return;}if(socket.encrypted!==true){fail('VERIFIED_METADATA_TLS_REQUIRED');return;}
    if(socket.authorized===true)send();else socket.once('secureConnect',send);});
  }catch{fail('RUNTIME_ACCESS_REQUEST_FAILED');}
 });
}
async function main(){const mode=process.argv[2]??'--validate';must(process.argv.length<=3&&['--validate','--inspect'].includes(mode),'EXACT_RUNTIME_ACCESS_MODE_REQUIRED');
 await loadApprovedInputs();if(mode==='--validate'){process.stdout.write(JSON.stringify({kind:'read-only-runtime-access-preparation',passed:true,
  fixedMetadataReads:5,networkCalls:0,settingsChanges:0,credentialValuesPrinted:false})+'\n');return;}
 let token='';for await(const chunk of process.stdin){token+=chunk;must(token.length<=2050,'PRIVATE_OWNER_INPUT_REQUIRED');}
 token=token.trim();must(token.length>8&&!/\s/.test(token),'PRIVATE_OWNER_INPUT_REQUIRED');
 const observations={};let networkCalls=0;
 for(const [kind,route]of Object.entries(routes)){networkCalls++;
  try{const response=await readOnly(token,route),value=response.value;let publicValue;
   if(kind==='temporaryAccess')publicValue={state:value.state??null,appliedSuccessfully:value.appliedSuccessfully??null};
   else if(kind==='userRoleMapping')publicValue={roles:(value.user_roles??[]).map(r=>({role:r.role,expiresAt:r.expires_at??null,
    networkRestrictionsPresent:!!r.allowed_networks,branchesOnly:r.branches_only??null}))};
   else if(kind==='tlsEnforcement')publicValue={database:value.currentConfig?.database??null,appliedSuccessfully:value.appliedSuccessfully??null};
   else if(kind==='secretNames')publicValue={modelKeyConfigured:Array.isArray(value)&&value.some(r=>r.name==='W5_OPENAI_API_KEY'),
    existingSecretValuesRead:false,secretCount:Array.isArray(value)?value.length:null};
   else publicValue={connections:Array.isArray(value)?value.map(r=>({databaseType:r.database_type,user:r.db_user,host:r.db_host,
    port:r.db_port,database:r.db_name,poolMode:r.pool_mode,maxClientConnections:r.max_client_conn,defaultPoolSize:r.default_pool_size})):[]};
   observations[kind]={read:true,...publicValue,responseSha256:response.responseSha256,actualFinishedAt:response.actualFinishedAt};
  }catch(error){observations[kind]={read:false,failureCode:error.publicCode??'RUNTIME_ACCESS_READ_FAILED',actualFinishedAt:new Date().toISOString()};}
 }
 token='';const result={kind:'actual-read-only-runtime-credential-access-investigation',actualFinishedAt:new Date().toISOString(),projectId:PROJECT,
  bundleSha256:BUNDLE,observations,networkCalls,databaseWrites:0,authWrites:0,settingsChanges:0,passwordsOrTokensOrSecretValuesPrinted:false,
  temporaryAccessReady:observations.temporaryAccess.state==='enabled'&&observations.temporaryAccess.appliedSuccessfully===true
   &&observations.userRoleMapping.roles?.some(r=>r.role==='postgres'&&(!r.expiresAt||r.expiresAt>Date.now()))===true,
  actualDatabaseConnectionsOpened:0,actualModelCalls:0,production:false,realBilling:false};
 const file=base+'runtime-access-investigation-20261013-r5-'+Date.now()+'.json',text=JSON.stringify(result,null,2)+'\n';
 const handle=await fs.open(path.join(root,file),'wx');try{await handle.writeFile(text);await handle.sync();}finally{await handle.close();}
 process.stdout.write(JSON.stringify({temporaryAccessReady:result.temporaryAccessReady,modelKeyConfigured:observations.secretNames.modelKeyConfigured??null,
  evidence:{path:file,sha256:hashBytes(text)},settingsChanged:false})+'\n');
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{
 process.stderr.write(JSON.stringify({failureCode:error.publicCode??'RUNTIME_ACCESS_INSPECTION_FAILED',rawErrorOrCredentialPrinted:false})+'\n');process.exitCode=1;});
