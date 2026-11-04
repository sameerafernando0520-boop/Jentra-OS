import {readBoundedJson} from './bounded_json.mjs';
import {runExternalForecast} from './worker_runtime.mjs';
import {invokeReviewedModel} from './model_runtime.mjs';
import {AuthenticatedForecastReader} from './model_reader.mjs';

const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
function response(status,body){return new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json','cache-control':'no-store'}});}
function bearer(req){const h=req.headers.get('authorization')??'';if(!/^Bearer [A-Za-z0-9._-]{32,4096}$/.test(h))throw Error('AUTH_REQUIRED');return h.slice(7);}
async function body(req){if(req.method!=='POST'||!req.headers.get('content-type')?.startsWith('application/json'))throw Error('VALIDATION_ERROR');
 const value=await readBoundedJson(req,65536);if(!value||typeof value!=='object'||Array.isArray(value))throw Error('VALIDATION_ERROR');return value;}
function failure(error){
 if(error.message==='WORKER_REQUEST_TIMEOUT')return response(408,{code:'REQUEST_TIMEOUT'});
 const allowed=new Set(['THROTTLED','QUOTA_EXCEEDED','INTEGRATION_ACCESS_DENIED','WORKER_ACCESS_DENIED','AUTH_REQUIRED','SOURCE_AUTHORITY_CHANGED',
  'VALIDATION_ERROR','WORKER_CONTRACT_MISMATCH','MODEL_CONTRACT_MISMATCH','MODEL_PROVIDER_UNAVAILABLE','MODEL_OUTCOME_UNKNOWN',
  'MODEL_OUTCOME_REQUIRES_REVIEW','TRUSTED_USAGE_MISMATCH','WORKER_PROVIDER_UNAVAILABLE']);
 const c=allowed.has(error.message)?error.message:'WORKER_PROVIDER_UNAVAILABLE';
 return response(/THROTTLED|QUOTA_EXCEEDED/.test(c)?429:/ACCESS_DENIED|AUTH_REQUIRED|AUTHORITY/.test(c)?403:/VALIDATION_ERROR|CONTRACT_MISMATCH/.test(c)?400:503,{code:c});
}

// Factories do not bind a listener or deploy a function. A reviewed launcher
// supplies the persistent ports and private configuration. Caller tokens are
// taken only from that caller's request; neither endpoint discovers a session.
export function createExternalCommandHandler({control,now=()=>Math.floor(Date.now()/1000)}){
 return async req=>{try{const token=bearer(req),request=await body(req);
  return response(200,await runExternalForecast({control,token,request,now:now()}));
 }catch(error){return failure(error);}};
}
export function createReviewedModelHandler({control,provider,policy,url,publishableKey,fetchImpl,readerFactory}){
 return async req=>{try{
  if(policy?.approved!==true||policy?.revision!==1||!provider)throw Error('MODEL_PROVIDER_UNAVAILABLE');
  const token=bearer(req),request=await body(req);
  const fields=['sourceId','scope','invocationId','usageEventId','maxTokens','periodStart','periodEnd'];
  if(Object.keys(request).length!==fields.length||!fields.every(k=>Object.hasOwn(request,k))||!uuid.test(request.sourceId)||
   !request.scope||Object.keys(request.scope).length!==3||!uuid.test(request.scope.tenantId)||!uuid.test(request.scope.legalEntityId)||
   (request.scope.branchId!==null&&!uuid.test(request.scope.branchId)))throw Error('VALIDATION_ERROR');
  const reader=readerFactory?readerFactory(token):new AuthenticatedForecastReader({url,publishableKey,accessToken:token,fetchImpl});
  return response(200,await invokeReviewedModel({reader,control,provider,request,policy}));
 }catch(error){return failure(error);}};
}
