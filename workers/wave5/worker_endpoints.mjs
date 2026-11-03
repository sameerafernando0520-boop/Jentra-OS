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
  'MODEL_OUTCOME_REQUIRES_REVIEW','TRUSTED_USAGE_MISMATCH','WORKER_PROVIDER_UNAVAILABLE','MODEL_INPUT_LIMIT']);
 const c=allowed.has(error.message)?error.message:'WORKER_PROVIDER_UNAVAILABLE';
 return response(/THROTTLED|QUOTA_EXCEEDED/.test(c)?429:/ACCESS_DENIED|AUTH_REQUIRED|AUTHORITY/.test(c)?403:/VALIDATION_ERROR|CONTRACT_MISMATCH|MODEL_INPUT_LIMIT/.test(c)?400:503,{code:c});
}

// Factories do not bind a listener or deploy a function. A reviewed launcher
// supplies the persistent ports and private configuration. Caller tokens are
// taken only from that caller's request; neither endpoint discovers a session.
export function createExternalCommandHandler({control,now=()=>Math.floor(Date.now()/1000)}){
 return async req=>{try{const token=bearer(req),request=await body(req);
  return response(200,await runExternalForecast({control,token,request,now:now()}));
 }catch(error){return failure(error);}};
}
export function createReviewedModelHandler({control,provider,policy,url,publishableKey,fetchImpl,readerFactory,reportFailure}){
 const callerKeyKind=typeof publishableKey!=='string'?'missing':/^sb_publishable_[A-Za-z0-9_-]+$/.test(publishableKey)?'opaque_publishable':/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(publishableKey)?'legacy_jwt':'unsupported';
 return async req=>{let stage='request.validate';try{
  if(policy?.approved!==true||policy?.revision!==1||!provider)throw Error('MODEL_PROVIDER_UNAVAILABLE');
  const token=bearer(req),request=await body(req);
  const fields=['sourceId','scope','invocationId','usageEventId','maxTokens','periodStart','periodEnd'];
  if(Object.keys(request).length!==fields.length||!fields.every(k=>Object.hasOwn(request,k))||!uuid.test(request.sourceId)||
   !request.scope||Object.keys(request.scope).length!==3||!uuid.test(request.scope.tenantId)||!uuid.test(request.scope.legalEntityId)||
   (request.scope.branchId!==null&&!uuid.test(request.scope.branchId)))throw Error('VALIDATION_ERROR');
  stage='reader.create';
  const reader=readerFactory?readerFactory(token):new AuthenticatedForecastReader({url,publishableKey,accessToken:token,fetchImpl});
  stage='model.invoke';
  return response(200,await invokeReviewedModel({reader,control,provider,request,policy,observeStage:value=>{stage=value;}}));
 }catch(error){
  // Fixed enum metadata only. In particular, never report the key or token.
  const frame=typeof error.stack==='string'?error.stack.match(/\b(model_reader|model_runtime|persistent_control|worker_endpoints|cloudflare_model_adapter|edge_runtime|scoped_runtime|bounded_json)\.mjs:(\d{1,6}):(\d{1,6})\b/):null;
  if(typeof reportFailure==='function')try{reportFailure({event:'wave5_model_handler_failure',callerKeyKind,stage,frame:frame?`${frame[1]}.mjs:${frame[2]}:${frame[3]}`:null,
   code:['WORKER_CONFIGURATION_INVALID','VALIDATION_ERROR','AUTH_REQUIRED'].includes(error.message)?error.message:'OTHER',
   errorKind:['Error','TypeError','SyntaxError','RangeError'].includes(error.name)?error.name:'Error'});}catch{}
  return failure(error);
 }};
}
