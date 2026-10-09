import {createWorkerRpc} from './persistent_control.mjs';

// The caller supplies its own authenticated token through the reviewed server
// request path. Never discover tokens or credentials from desktop/local stores.
export class AuthenticatedForecastReader {
 constructor({url,publishableKey,accessToken,fetchImpl}) {
  if(typeof accessToken!=='string'||accessToken.length<32)throw Error('AUTH_REQUIRED');
  const baseFetch=fetchImpl??fetch;
  this.rpc=createWorkerRpc({url,serviceKey:publishableKey,fetchImpl:(target,options)=>baseFetch(target,{...options,
    headers:{...options.headers,authorization:`Bearer ${accessToken}`}})});
 }
 scope(request){const s=request.scope;if(!s)throw Error('VALIDATION_ERROR');return {p_tenant_id:s.tenantId,p_legal_entity_id:s.legalEntityId,p_branch_id:s.branchId};}
 async forecast(request){return this.rpc('get_ai_forecast_evidence',{...this.scope(request),p_forecast_id:request.sourceId});}
 async authorize(request,evidence){
  const current=await this.forecast(request);
  if(current.sourceId!==evidence.sourceId||current.sourceHash!==evidence.sourceHash||
   ['tenantId','legalEntityId','branchId'].some(key=>current.scope?.[key]!==evidence.scope?.[key]))throw Error('SOURCE_AUTHORITY_CHANGED');
 }
}
