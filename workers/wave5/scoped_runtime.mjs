import {createWorkerRpc} from './persistent_control.mjs';

const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
// All calls from the existing persistent controls pass through the server's
// reviewed runtime allowlist. A caller cannot select an unscoped RPC name.
export function createScopedWorkerRpc({runtimeId,...transport}) {
 if(!uuid.test(runtimeId))throw Error('WORKER_CONFIGURATION_INVALID');
 const rpc=createWorkerRpc(transport);
 return async(name,p)=>{
  let action,payload;
  if(name==='wave5_delivery_worker'){action=`delivery.${p.p_action}`;payload=p.p_payload;}
  else if(name==='wave5_model_worker'){action=`model.${p.p_action}`;payload=p.p_payload;}
  else if(name==='wave5_external_worker'){action=`external.${p.p_action}`;payload=p.p_payload;}
  else if(name==='wave5_worker_entitlement'){action='entitlement';payload={scope:p.p_scope};}
  else if(name==='wave5_reserve_usage'){action='usage.reserve';payload={tenantId:p.p_tenant_id,invocationId:p.p_invocation_id,
   metric:p.p_metric_code,periodStart:p.p_period_start,periodEnd:p.p_period_end,quantity:p.p_quantity};}
  else if(name==='wave5_settle_usage'){action='usage.settle';payload={tenantId:p.p_tenant_id,invocationId:p.p_invocation_id,eventId:p.p_event_id,quantity:p.p_quantity};}
  else if(name==='wave5_subscription_due'){action='subscription.due';payload={after:p.p_after};}
  else if(name==='apply_synthetic_subscription'){action='subscription.apply';payload={tenantId:p.p_tenant_id,revisionId:p.p_revision_id};}
  else if(name==='wave5_health_collect'){action='health.collect';payload={collectionId:p.p_collection_id,tenantId:p.p_tenant_id};}
  else throw Error('WORKER_RPC_NOT_ALLOWLISTED');
  return rpc('wave5_runtime_worker',{p_runtime_id:runtimeId,p_action:action,p_payload:payload});
 };
}
