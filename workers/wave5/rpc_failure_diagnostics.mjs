import {readBoundedJson} from './bounded_json.mjs';

const rpcNames=new Set(['get_ai_forecast_evidence','wave5_runtime_worker','wave5_edge_control']);
const errorKinds=new Set(['Error','TypeError','AbortError','TimeoutError']);
const errorCode=/^(?:[0-9A-Z]{5}|PGRST[0-9]{3})$/;

// Emit only fixed RPC names, status and machine error codes. Never emit request
// bodies, headers, URLs, credentials, SQL messages, caller IDs or model content.
// Observability cannot change the returned response or trigger another send.
export function createRpcFailureDiagnosticFetch({url,fetchImpl=fetch,emit}){
 const origin=new URL(url).origin;
 if(typeof fetchImpl!=='function'||typeof emit!=='function')throw Error('WORKER_CONFIGURATION_INVALID');
 const record=value=>{try{emit(Object.freeze(value));}catch{}};
 return async(input,options)=>{
  const target=new URL(input instanceof Request?input.url:input);
  const name=target.origin===origin&&target.pathname.startsWith('/rest/v1/rpc/')
   ?target.pathname.slice('/rest/v1/rpc/'.length):null;
  const observed=rpcNames.has(name);
  let response;
  try{response=await fetchImpl(input,options);}
  catch(error){
   if(observed)record({event:'wave5_rpc_failure',rpc:name,stage:'transport',errorKind:errorKinds.has(error?.name)?error.name:'Error'});
   throw error;
  }
  if(observed&&!response.ok){
   let code=null;
   try{
    const detail=await readBoundedJson(response.clone(),4096,{signal:options?.signal??AbortSignal.timeout(1000)});
    if(typeof detail?.code==='string'&&errorCode.test(detail.code))code=detail.code;
   }catch{}
   record({event:'wave5_rpc_failure',rpc:name,stage:'response',status:response.status,code});
  }
  return response;
 };
}
