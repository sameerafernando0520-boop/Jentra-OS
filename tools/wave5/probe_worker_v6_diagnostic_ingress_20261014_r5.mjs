import https from 'node:https';
import fs from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {hashBytes} from './runtime_contract.mjs';
if(process.argv.length>2)throw Error('FIXED_V6_WORKER_PROBE_REQUIRED');
const base=new URL('../../docs/verification/wave5/',import.meta.url);
const read=async name=>JSON.parse(await fs.readFile(new URL(name,base),'utf8'));
const owner=await read('worker-v6-diagnostic-technical-operation-decision-20261014-r5.json');
const proof=await read('worker-v6-diagnostic-deployment-source-verification-20261014-r5.json');
if(owner.decision!=='approve'||owner.candidateBundleSha256!=='091d42d339733ae73838bdbc720a714c9a9b673b03ce41b972b9b61cd2017718'||proof.candidateBundleSha256!==owner.candidateBundleSha256||proof.independentlyReturnedSourceModules!==22||!proof.allReturnedSourceHashesMatch||!proof.existingPeopleFunctionsUnchanged)throw Error('EXACT_APPROVED_V6_READBACK_REQUIRED');
const startedAt=new Date().toISOString(),target='https://xpdoufauvrbdmxgngetv.supabase.co/functions/v1/wave5-runtime/schedule',bytes=Buffer.from('{}');
await fs.writeFile(new URL('worker-v6-diagnostic-fixed-probe-once-20261014-r5.json',base),JSON.stringify({kind:'bounded-delegated-v6-public-probe-once-intent',startedAt,target,maximumRequests:1,automaticRetry:false,suppliedCredentials:false,candidateBundleSha256:owner.candidateBundleSha256},null,2)+'\n',{flag:'wx'});
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
    resolve({status:res.statusCode,responseRequestId,responseSha256:hashBytes(raw),responseBytes:raw.length,code:['WORKER_ACCESS_DENIED','NOT_FOUND','WORKER_PROVIDER_UNAVAILABLE','UNAUTHORIZED','VALIDATION_ERROR'].includes(value?.code)?value.code:null,handlerNotFoundShape:value?.code==='NOT_FOUND'&&Object.keys(value).length===1,gatewayNotFoundShape:value?.code==='NOT_FOUND'&&typeof value?.message==='string',expectedUnauthenticatedHandlerDenial:res.statusCode===403&&value?.code==='WORKER_ACCESS_DENIED'&&Object.keys(value).length===1});});
  });
  timer=setTimeout(()=>fail('WORKER_PROBE_DEADLINE'),12000);
  request.on('error',()=>fail('WORKER_PROBE_TRANSPORT_UNCERTAIN'));
  request.once('socket',socket=>{const send=()=>{if(socket.encrypted!==true||socket.authorized!==true){fail('VERIFIED_WORKER_PROBE_TLS_REQUIRED');return;}dispatched=true;request.end(bytes);};if(socket.authorized===true)send();else socket.once('secureConnect',send);});
 });
 const record={kind:'one-fixed-delegated-v6-unauthenticated-worker-ingress-probe',startedAt,finishedAt:new Date().toISOString(),target,dispatched,requests:1,redirectsFollowed:0,automaticRetries:0,suppliedCredentials:false,cookies:false,verifiedTls:true,bodyBytes:2,totalDeadlineMs:12000,...response,actualInternalRequestUrlObserved:false,finiteDiagnosticNotYetQueried:true,schedulesResumed:false,deliveryOrModelCallClaimed:false,rawBodyOrHeadersPrinted:false};
 const name='worker-v6-diagnostic-fixed-unauthenticated-probe-20261014-r5.json';await fs.writeFile(new URL(name,base),JSON.stringify(record,null,2)+'\n',{flag:'wx'});process.stdout.write(JSON.stringify(record)+'\n');
}catch(error){await fs.writeFile(new URL('worker-v6-diagnostic-fixed-probe-stop-20261014-r5.json',base),JSON.stringify({kind:'preserved-v6-public-probe-stop',startedAt,stoppedAt:new Date().toISOString(),failureCode:error.message,dispatched,automaticRetry:false,originalIntentPreserved:true,schedulesResumed:false,privateValuesPrinted:false},null,2)+'\n',{flag:'wx'});throw error;}
