import {createHash} from 'node:crypto';
import {edgeConfiguration as config} from '../../workers/wave5/edge_configuration.mjs';
import {readBoundedBytes,waitForSignal} from '../../workers/wave5/bounded_json.mjs';

// Only these unsigned, empty requests are supported. This module cannot accept
// credentials, a caller-selected host, a schedule key, a model input or a send.
const endpoints=Object.freeze([
 {name:'schedule',url:config.workerUrl+'/schedule',code:'WORKER_ACCESS_DENIED'},
 {name:'external-forecast',url:config.workerUrl+'/external/forecast',code:'AUTH_REQUIRED'},
 {name:'model-suggestion',url:config.workerUrl+'/model/suggestion',code:'AUTH_REQUIRED'},
 {name:'receiver',url:config.receiverUrl,code:'INTEGRATION_ACCESS_DENIED'},
].map(Object.freeze));
const allowedCodes=new Set([...endpoints.map(e=>e.code),'MODEL_PROVIDER_UNAVAILABLE','WORKER_PROVIDER_UNAVAILABLE',
 'NOT_FOUND','UNAUTHORIZED','RECEIVER_UNAVAILABLE','VALIDATION_ERROR']);
const uuid=/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i;
const stamp=()=>new Date().toISOString();

export async function probeHostedResponses({fetchImpl=fetch,record,timeoutMs=12000}={}){
 if(typeof record!=='function'||!Number.isSafeInteger(timeoutMs)||timeoutMs<1||timeoutMs>12000)
  throw Error('HOSTED_PROBE_CONFIGURATION_INVALID');
 const startedAt=stamp(),observations=[];
 for(const [endpointIndex,endpoint] of endpoints.entries()){
  const intent={endpointIndex,endpoint:endpoint.name,target:endpoint.url,startedAt:stamp(),
   method:'POST',requestBytes:2,credentialsSupplied:false,automaticRetry:false};
  // Durable intent is required before dispatch. A journal failure is fatal and
  // must not be swallowed as a network outcome or permit the next request.
  await record({type:'request-intent',...intent});
  const outcome={...intent,finishedAt:null,status:null,requestId:null,responseSha256:null,
   responseBytes:null,code:null,state:'transport-unconfirmed'};
  try{
   const signal=AbortSignal.timeout(timeoutMs);
   const response=await waitForSignal(fetchImpl(new URL(endpoint.url),{method:'POST',
    headers:{'content-type':'application/json'},body:'{}',credentials:'omit',redirect:'manual',signal}),signal);
   outcome.status=response.status;
   const requestId=response.headers.get('sb-request-id');
   outcome.requestId=uuid.test(requestId??'')?requestId:null;
   const bytes=await readBoundedBytes(response,1024,{signal});
   outcome.responseSha256=createHash('sha256').update(bytes).digest('hex');
   outcome.responseBytes=bytes.length;
   let value;
   try{value=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{}
   // Raw bodies, redirects, headers and provider diagnostics never enter the
   // public evidence. An expected code with extra fields is not an exact denial.
   const exact=value&&typeof value==='object'&&!Array.isArray(value)&&Object.keys(value).length===1&&Object.hasOwn(value,'code');
   outcome.code=allowedCodes.has(value?.code)?value.code:null;
   outcome.state=exact&&response.status===403&&value.code===endpoint.code?'denial-verified'
    :exact&&endpoint.name==='model-suggestion'&&response.status===503&&value.code==='MODEL_PROVIDER_UNAVAILABLE'
     ?'provider-unavailable':'unexpected-response';
  }catch{
   // Aborted/disconnected sends remain uncertain. There is never a retry.
  }
  outcome.finishedAt=stamp();
  await record({type:'request-result',...outcome});
  observations.push(outcome);
 }
 return {kind:'jentra-ai-integrations-public-hosted-probe',contractRevision:1,projectId:config.projectId,
  startedAt,finishedAt:stamp(),maximumRequests:4,requests:observations.length,credentialsSupplied:false,
  redirectsFollowed:0,automaticRetries:0,observations,
  unsignedAuthenticationVerified:observations.every(o=>o.state==='denial-verified'),
  hostedModelResponseVerified:false,usageAccountingVerified:false,externalDeliveryVerified:false,
  installedSourceVerified:false,runtimeAuthorityVerified:false,
  boundary:'Unsigned HTTP observations only. A denial does not prove an authenticated model response, trusted usage, delivery, installed source bytes or current runtime authority.'};
}
