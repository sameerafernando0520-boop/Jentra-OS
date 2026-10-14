import https from 'node:https';
import fs from 'node:fs/promises';
import {hashBytes} from './runtime_contract.mjs';
if(process.argv.length>2)throw Error('FIXED_V7_WORKER_PROBE_REQUIRED');
const base=new URL('../../docs/verification/wave5/',import.meta.url);
async function exact(name,pin){const b=await fs.readFile(new URL(name,base));if(hashBytes(b)!==pin)throw Error('EXACT_APPROVED_V7_PROBE_EVIDENCE_REQUIRED');return JSON.parse(b);}
const owner=await exact('worker-v7-provider-owner-decision-20261014-r5.json','0f513290971c544eaabd15a56aca78ff5a6a5ddc09e2a8dcca52f87178ef0066');
const proof=await exact('worker-v7-provider-deployment-source-verification-20261014-r5-a2.json','9deaf816923888e44b7b35fa0b961b2915f3ce7c6df41df5b184a3391adfa9e6');
if(owner.decision!=='approve'||owner.operationBundleSha256!=='24d74074ebc3b5e92e7fb047743b047952a85deeabe8a7def20470b0ed678493'||proof.operationBundleSha256!==owner.operationBundleSha256||proof.independentlyReturnedSourceModules!==25||!proof.allReturnedSourceHashesMatch||!proof.existingPeopleFunctionsUnchanged||Date.now()>=Date.parse(owner.originalAuthorityExpiresAt))throw Error('EXACT_APPROVED_ACTIVE_V7_READBACK_REQUIRED');
const startedAt=new Date().toISOString(),target='https://xpdoufauvrbdmxgngetv.supabase.co/functions/v1/wave5-runtime/schedule',bytes=Buffer.from('{}');
await fs.writeFile(new URL('worker-v7-provider-fixed-probe-once-20261014-r5.json',base),JSON.stringify({kind:'bounded-direct-human-approved-v7-public-probe-once-intent',startedAt,target,maximumRequests:1,automaticRetry:false,suppliedCredentials:false,operationBundleSha256:owner.operationBundleSha256},null,2)+'\n',{flag:'wx'});
let dispatched=false,request;
try{
 const response=await new Promise((resolve,reject)=>{
  let done=false,size=0,timer;const chunks=[];
  const fail=code=>{if(done)return;done=true;clearTimeout(timer);request?.destroy();reject(Error(code));};
  request=https.request(target,{method:'POST',headers:{'Content-Type':'application/json','Content-Length':bytes.length},rejectUnauthorized:true,agent:false},res=>{
   res.on('error',()=>fail('WORKER_PROBE_RESPONSE_UNCERTAIN'));
   res.on('data',chunk=>{size+=chunk.length;if(size>1024)fail('BOUNDED_WORKER_RESPONSE_REQUIRED');else chunks.push(chunk);});
   res.on('end',()=>{if(done)return;done=true;clearTimeout(timer);const raw=Buffer.concat(chunks);let value=null;try{value=JSON.parse(raw);}catch{}
    const requestId=res.headers['sb-request-id'];const responseRequestId=typeof requestId==='string'&&/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(requestId)?requestId:null;
    resolve({status:res.statusCode,responseRequestId,responseSha256:hashBytes(raw),responseBytes:raw.length,code:['WORKER_ACCESS_DENIED','NOT_FOUND','WORKER_PROVIDER_UNAVAILABLE','UNAUTHORIZED','VALIDATION_ERROR'].includes(value?.code)?value.code:null,expectedUnauthenticatedHandlerDenial:res.statusCode===403&&value?.code==='WORKER_ACCESS_DENIED'&&Object.keys(value).length===1});});
  });
  timer=setTimeout(()=>fail('WORKER_PROBE_DEADLINE'),12000);
  request.on('error',()=>fail('WORKER_PROBE_TRANSPORT_UNCERTAIN'));
  request.once('socket',socket=>{const send=()=>{if(socket.encrypted!==true||socket.authorized!==true){fail('VERIFIED_WORKER_PROBE_TLS_REQUIRED');return;}dispatched=true;request.end(bytes);};if(socket.authorized===true)send();else socket.once('secureConnect',send);});
 });
 const record={kind:'one-fixed-direct-human-approved-v7-unauthenticated-worker-probe',startedAt,finishedAt:new Date().toISOString(),target,dispatched,requests:1,redirectsFollowed:0,automaticRetries:0,suppliedCredentials:false,cookies:false,verifiedTls:true,bodyBytes:2,totalDeadlineMs:12000,...response,operationBundleSha256:owner.operationBundleSha256,schedulesResumed:false,actualProviderKeyAuthorizationVerified:false,deliveryOrModelCallClaimed:false,rawBodyOrHeadersPrinted:false};
 const name='worker-v7-provider-fixed-unauthenticated-probe-20261014-r5.json';await fs.writeFile(new URL(name,base),JSON.stringify(record,null,2)+'\n',{flag:'wx'});process.stdout.write(JSON.stringify(record)+'\n');
 if(!response.expectedUnauthenticatedHandlerDenial)throw Error('EXPECTED_V7_UNSIGNED_HANDLER_DENIAL_REQUIRED');
}catch(error){await fs.writeFile(new URL('worker-v7-provider-fixed-probe-stop-20261014-r5.json',base),JSON.stringify({kind:'preserved-v7-public-probe-stop',startedAt,stoppedAt:new Date().toISOString(),failureCode:error.message,dispatched,automaticRetry:false,originalIntentPreserved:true,schedulesResumed:false,privateValuesPrinted:false},null,2)+'\n',{flag:'wx'});throw error;}
