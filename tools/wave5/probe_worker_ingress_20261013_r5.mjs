import https from 'node:https';
import fs from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {hashBytes} from './runtime_contract.mjs';
if(process.argv.length>2)throw Error('FIXED_WORKER_INGRESS_PROBE_REQUIRED');
const target='https://xpdoufauvrbdmxgngetv.supabase.co/functions/v1/wave5-runtime/schedule';
const startedAt=new Date().toISOString(),bytes=Buffer.from('{}');
let dispatched=false;
const response=await new Promise((resolve,reject)=>{
 const request=https.request(target,{method:'POST',headers:{'Content-Type':'application/json','Content-Length':bytes.length},rejectUnauthorized:true,agent:false},res=>{
  let size=0;const chunks=[];
  res.on('data',chunk=>{size+=chunk.length;if(size>1024){request.destroy();reject(Error('BOUNDED_WORKER_RESPONSE_REQUIRED'));}else chunks.push(chunk);});
  res.on('error',()=>reject(Error('WORKER_PROBE_RESPONSE_UNCERTAIN')));
  res.on('end',()=>{const raw=Buffer.concat(chunks);let value=null;try{value=JSON.parse(raw);}catch{}
   resolve({status:res.statusCode,responseSha256:hashBytes(raw),responseBytes:raw.length,
    code:['NOT_FOUND','SCHEDULE_AUTHORIZATION_REQUIRED','FORBIDDEN','UNAUTHORIZED'].includes(value?.code)?value.code:null,
    handlerNotFoundShape:value?.code==='NOT_FOUND'&&Object.keys(value).length===1,
    gatewayNotFoundShape:value?.code==='NOT_FOUND'&&typeof value?.message==='string'});});
 });
 request.setTimeout(12000,()=>{request.destroy();reject(Error('WORKER_PROBE_TIMEOUT'));});
 request.on('error',()=>reject(Error('WORKER_PROBE_TRANSPORT_UNCERTAIN')));
 request.once('socket',socket=>{const send=()=>{if(socket.encrypted!==true||socket.authorized!==true){request.destroy();reject(Error('VERIFIED_WORKER_PROBE_TLS_REQUIRED'));return;}
  dispatched=true;request.end(bytes);};if(socket.authorized===true)send();else socket.once('secureConnect',send);});
});
const record={kind:'one-fixed-unauthenticated-worker-ingress-probe',startedAt,finishedAt:new Date().toISOString(),target,dispatched,
 requests:1,redirectsFollowed:0,automaticRetries:0,suppliedCredentials:false,cookies:false,verifiedTls:true,bodyBytes:2,...response,
 actualInternalRequestUrlObserved:false,deliveryOrModelCallClaimed:false,rawBodyOrHeadersPrinted:false};
const file=fileURLToPath(new URL('../../docs/verification/wave5/worker-routing-fixed-unauthenticated-probe-20261013-r5.json',import.meta.url));
await fs.writeFile(file,JSON.stringify(record,null,2)+'\n',{flag:'wx'});
process.stdout.write(JSON.stringify(record)+'\n');
