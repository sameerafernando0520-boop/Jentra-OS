import {serviceProviderHeaders} from './provider_credentials_20261014_r5_v7.mjs';
import {createHash} from 'node:crypto';
import {Buffer} from 'node:buffer';
import {readBoundedJson} from './bounded_json.mjs';

/** Supabase RPC transport. Secrets are supplied by a reviewed server launcher,
 * never discovered from local files, desktop sessions or other chats. */
export function createWorkerRpc({url,serviceKey,fetchImpl=fetch}) {
 const target=new URL(url);
 if(target.protocol!=='https:' || target.username || target.password || target.pathname!=='/' ||
    !target.hostname.endsWith('.supabase.co') || typeof serviceKey!=='string' || serviceKey.length<32) throw Error('WORKER_CONFIGURATION_INVALID');
 const providerHeaders=serviceProviderHeaders(serviceKey);
 return async(name,params)=>{
  const response=await fetchImpl(new URL(`/rest/v1/rpc/${name}`,target),{method:'POST',
   headers:{...providerHeaders,'content-profile':'api','accept-profile':'api','content-type':'application/json'},
   body:JSON.stringify(params),redirect:'error',signal:AbortSignal.timeout(15000)});
  if(!response.ok) throw Error(response.status===401||response.status===403?'WORKER_ACCESS_DENIED':'WORKER_PROVIDER_UNAVAILABLE');
  return readBoundedJson(response);
 };
}

export class PersistentDeliveryControl {
 constructor(rpc){this.rpc=rpc;}
 worker(action,payload={}){return this.rpc('wave5_delivery_worker',{p_action:action,p_payload:payload});}
 readiness(){return this.worker('readiness');}
 claimCommittedDelivery(){return this.worker('claim');}
 authorizeDelivery(job){return this.worker('authorize',{deliveryId:job.deliveryId,leaseId:job.leaseId});}
 reserveUsage(q){return this.rpc('wave5_reserve_usage',{p_tenant_id:q.tenantId,p_invocation_id:q.invocationId,
  p_metric_code:q.metric,p_period_start:q.periodStart,p_period_end:q.periodEnd,p_quantity:q.quantity});}
 settleUsage(q){return this.rpc('wave5_settle_usage',{p_tenant_id:q.tenantId,p_invocation_id:q.invocationId,p_event_id:q.eventId,p_quantity:q.quantity});}
 recordDeliveryOutcome(job,outcome){return this.worker('outcome',{deliveryId:job.deliveryId,leaseId:job.leaseId,
  state:outcome.state,httpStatus:outcome.httpStatus??null});}
 reconcileAcknowledged(){return this.worker('settle_acknowledged');}
 applySyntheticSubscription(tenantId,revisionId){return this.rpc('apply_synthetic_subscription',{p_tenant_id:tenantId,p_revision_id:revisionId});}
 dueSyntheticSubscriptions(after=null){return this.rpc('wave5_subscription_due',{p_after:after});}
 collectHealth(collectionId,tenantId=null){return this.rpc('wave5_health_collect',{p_collection_id:collectionId,p_tenant_id:tenantId});}
 async deliverySecret(job,vault){
  const ref=await this.worker('key_ref',{deliveryId:job.deliveryId,leaseId:job.leaseId});
  const value=await vault.read(ref);
  if(!Buffer.isBuffer(value)||value.length<32||value.length>128) throw Error('DELIVERY_KEY_UNAVAILABLE');
  return value;
 }
}

/** Bounded scheduler. Reconciles persisted ACKs before any new network work.
 * The launcher owns scheduling, vault and approved receiver configuration. */
export async function runDeliveryBatch({control,vault,resolve,post,now,limit=20,signal}) {
 if(!Number.isInteger(limit)||limit<1||limit>100) throw Error('WORKER_LIMIT_INVALID');
 const {runDelivery}=await import('./worker_runtime.mjs');
 await control.reconcileAcknowledged();
 const outcomes=[];
 for(let i=0;i<limit && !signal?.aborted;i++) {
  let selected;
  const ports=Object.create(control);
  ports.claimCommittedDelivery=async()=>{selected=await control.claimCommittedDelivery();return selected;};
  const result=await runDelivery({control:ports,secrets:{deliveryKey:()=>control.deliverySecret(selected,vault)},resolve,post,now:now(),signal});
  if(result.state==='idle') break;
  outcomes.push({state:result.state,eventId:result.eventId,attempt:result.attempt});
 }
 return outcomes;
}

export const credentialDigest=token=>createHash('sha256').update(token,'utf8').digest('hex');

export class PersistentInvocationControl extends PersistentDeliveryControl {
 async readiness(){
  const result=await super.readiness();
  // Verify the separate invocation contract exists; table names are not a
  // readiness claim. The launcher must install/review this candidate first.
  await this.rpc('wave5_model_worker',{p_action:'readiness',p_payload:{}});
  return {...result,providers:{...result.providers,'external_forecast.v1':1}};
 }
 findCredential(token){return this.rpc('wave5_external_worker',{p_action:'credential',p_payload:{tokenHash:credentialDigest(token)}});}
 entitlement(scope){return this.rpc('wave5_worker_entitlement',{p_scope:scope});}
 reserveExternalRequest(credential,request){return this.rpc('wave5_external_worker',{p_action:'reserve',p_payload:{tokenHash:credential.tokenHash,request}});}
 dispatchForecast(credential,request){return this.rpc('wave5_external_worker',{p_action:'dispatch',p_payload:{tokenHash:credential.tokenHash,request}});}
 beginModelInvocation(request){return this.rpc('wave5_model_worker',{p_action:'begin',p_payload:request});}
 recordModelOutcome(invocationId,outcome){return this.rpc('wave5_model_worker',{p_action:'outcome',p_payload:{invocationId,...outcome}});}
}
