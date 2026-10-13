import fs from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {hashBytes} from './runtime_contract.mjs';
const sourceFile=new URL('./supabase_http_transport.mjs',import.meta.url),output=new URL('./delivery_transport_20261013_r5.mjs',import.meta.url);
let source=await fs.readFile(sourceFile,'utf8');
if(hashBytes(source)!=='7815b9c8c18bd5d2375480706579c7dd9583b1e95e0424a2178f7b9b5db265c9')throw Error('EXACT_VERIFIED_TRANSPORT_SOURCE_REQUIRED');
const before=".map(contract => contract.signature.split('(')[0].replace(/^api\\./, '')));";
if(source.split(before).length!==2)throw Error('EXACT_TRANSPORT_ALLOWLIST_REQUIRED');
source=source.replace(before,".map(contract => contract.signature.split('(')[0].replace(/^api\\./, '')).concat(['wave5_delivery_review','wave5_integration_list']));");
const handle=await fs.open(output,'wx');try{await handle.writeFile(source);await handle.sync();}finally{await handle.close();}
process.stdout.write(JSON.stringify({path:fileURLToPath(output),sha256:hashBytes(source),networkCalls:0,
 additionalRpcs:['wave5_delivery_review','wave5_integration_list'],tlsAndSessionGuardsPreserved:true})+'\n');
