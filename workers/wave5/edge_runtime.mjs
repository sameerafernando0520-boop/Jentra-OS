import {lookup} from 'node:dns/promises';
import {createHash,randomUUID} from 'node:crypto';
import {Buffer} from 'node:buffer';
import {PersistentInvocationControl,createWorkerRpc,runDeliveryBatch} from './persistent_control.mjs';
import {createScopedWorkerRpc} from './scoped_runtime.mjs';
import {createExternalCommandHandler,createReviewedModelHandler} from './worker_endpoints.mjs';
import {runSyntheticSubscriptionBatch} from './subscription_schedule.mjs';
import {OpenAIResponsesProvider} from './openai_model_adapter.mjs';
import {pinnedHttpsPost} from './integration_policy.mjs';
import {readBoundedJson} from './bounded_json.mjs';
import {edgeConfiguration} from './edge_configuration.mjs';

const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
const hex=/^[a-f0-9]{64}$/;
const reply=(status,body)=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json','cache-control':'no-store'}});
function required(v){if(typeof v!=='string'||v.length<32)throw Error('WORKER_PROVIDER_UNAVAILABLE');return v;}
function envValue(env,name){return typeof env.get==='function'?env.get(name):env[name];}
export async function resolvePublicAddresses(host,resolver=lookup){
 return (await resolver(host,{all:true})).map(item=>item.address);
}

// Factory construction performs no network, key reads, deployment or scheduling.
/**
 * @param {{env: {get(name: string): string | undefined} | Record<string, string | undefined>,
 * config?: typeof edgeConfiguration, fetchImpl?: typeof fetch, resolve?: Function,
 * post?: Function, controlFactory?: Function, edgeRpcFactory?: Function,
 * providerFactory?: Function}} options
 */
export function createEdgeRuntime({env,config=edgeConfiguration,fetchImpl=fetch,resolve=resolvePublicAddresses,post=pinnedHttpsPost,
 controlFactory,edgeRpcFactory,providerFactory}){
 let active=0;
 return async req=>{
  if(active>=config.maxConcurrentRequests)return reply(429,{code:'THROTTLED'});
  active++;
  const keys=[];
  try{
   const url=new URL(req.url),base=new URL(config.workerUrl);
   if(url.origin!==base.origin||req.method!=='POST')return reply(404,{code:'NOT_FOUND'});
   const route=url.pathname.slice(base.pathname.length);
   if(!url.pathname.startsWith(base.pathname+'/')||url.search||!['/schedule','/external/forecast','/model/suggestion'].includes(route))return reply(404,{code:'NOT_FOUND'});
   if(Number(req.headers.get('content-length'))>config.maxRequestBytes)return reply(413,{code:'VALIDATION_ERROR'});
   // These are injected platform variables. No desktop or other-chat credential
   // is discovered, returned or logged.
   if(envValue(env,'SUPABASE_URL')!==config.url)throw Error('WORKER_PROVIDER_UNAVAILABLE');
   const serviceKey=required(envValue(env,'SUPABASE_SERVICE_ROLE_KEY'));
   if(!/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(serviceKey))throw Error('WORKER_PROVIDER_UNAVAILABLE');
   const budget=AbortSignal.timeout(65000);
   const boundedFetch=(url,options={})=>fetchImpl(url,{...options,signal:options.signal?AbortSignal.any([options.signal,budget]):budget});
   const transport={runtimeId:config.runtimeId,url:config.url,serviceKey,fetchImpl:boundedFetch};
   const control=controlFactory?controlFactory(transport):new PersistentInvocationControl(createScopedWorkerRpc(transport));
   const raw=edgeRpcFactory?edgeRpcFactory(transport):createWorkerRpc(transport);
   const edge=(action,payload)=>raw('wave5_edge_control',{p_runtime_id:config.runtimeId,p_action:action,p_payload:payload});
   if(route==='/schedule'){
    const token=req.headers.get('x-jentra-schedule-key');
    if(!hex.test(token??''))return reply(403,{code:'WORKER_ACCESS_DENIED'});
    const request=await readBoundedJson(req,1024);
    if(!request||Object.keys(request).length!==2||!uuid.test(request.tickId)||!['delivery','subscription','health'].includes(request.kind))return reply(400,{code:'VALIDATION_ERROR'});
    const permit=await edge('begin_tick',{...request,secretHash:createHash('sha256').update(token).digest('hex')});
    if(permit?.permitted!==true)return reply(200,{state:'already_running'});
    let summary;
    try{
     await control.readiness();
     if(request.kind==='delivery'){
      const vault={read:async ref=>{
       const answer=await edge('key',{ref});
       if(!hex.test(answer?.value??''))throw Error('DELIVERY_KEY_UNAVAILABLE');
       const bytes=Buffer.from(answer.value,'hex');keys.push(bytes);return bytes;
      }};
      const outcomes=await runDeliveryBatch({control,vault,resolve,post,now:()=>Math.floor(Date.now()/1000),limit:config.maxDeliveryBatch,signal:AbortSignal.timeout(55000)});
      summary={count:outcomes.length,states:outcomes.map(o=>o.state)};
     }else if(request.kind==='subscription'){
      const batch=await runSyntheticSubscriptionBatch({control,limit:config.maxSubscriptionBatch,signal:AbortSignal.timeout(55000)});
      summary={count:batch.results.length,states:batch.results.map(o=>o.state)};
     }else {await control.collectHealth(randomUUID(),permit.tenantId);summary={count:1,states:['collected']};}
     await edge('finish_tick',{tickId:request.tickId,success:true,summary});
     return reply(200,{state:'completed',...summary});
    }catch{
     await edge('finish_tick',{tickId:request.tickId,success:false,summary:{count:0,states:['unconfirmed']}}).catch(()=>{});
     return reply(503,{code:'WORKER_PROVIDER_UNAVAILABLE'});
    }
   }
   if(route==='/external/forecast')return await createExternalCommandHandler({control})(req);
   const apiKey=envValue(env,'W5_OPENAI_API_KEY');
   if(typeof apiKey!=='string'||apiKey.length<32)return reply(503,{code:'MODEL_PROVIDER_UNAVAILABLE'});
   const publishableKey=required(envValue(env,'SUPABASE_ANON_KEY'));
   const provider=providerFactory?providerFactory({apiKey,review:config.model,fetchImpl:boundedFetch}):new OpenAIResponsesProvider({apiKey,review:config.model,fetchImpl:boundedFetch});
   return await createReviewedModelHandler({control,provider,policy:config.model,url:config.url,publishableKey,fetchImpl:boundedFetch})(req);
  }catch(error){
   if(error instanceof SyntaxError||/VALIDATION_ERROR|WORKER_OUTPUT_LIMIT/.test(error.message))return reply(400,{code:'VALIDATION_ERROR'});
   return reply(/ACCESS_DENIED|SCOPE_DENIED/.test(error.message)?403:503,{code:/ACCESS_DENIED|SCOPE_DENIED/.test(error.message)?'WORKER_ACCESS_DENIED':'WORKER_PROVIDER_UNAVAILABLE'});
  }
  finally {for(const key of keys)key.fill(0);active--;}
 };
}
