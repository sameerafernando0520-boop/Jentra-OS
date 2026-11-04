import {serviceCredentialKind} from './provider_credentials_20261014_r5_v7.mjs';
import {edgeRoute} from './edge_route_20261014_r5_v6.mjs';
import {createHash,timingSafeEqual} from 'node:crypto';
import {Buffer} from 'node:buffer';
import {createWorkerRpc} from './persistent_control_20261014_r5_v7.mjs';
import {forecastEvent,signDelivery} from './integration_policy.mjs';
import {edgeConfiguration} from './edge_configuration.mjs';
import {readBoundedBytes} from './bounded_json.mjs';

const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
const hex=/^[a-f0-9]{64}$/;
const reply=(status,body,headers={})=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json','cache-control':'no-store',...headers}});
const value=(env,name)=>typeof env.get==='function'?env.get(name):env[name];
function waitWithinBudget(ms,signal){
 return new Promise((resolve,reject)=>{
  const timer=setTimeout(done,ms);
  function cleanup(){clearTimeout(timer);signal?.removeEventListener('abort',cancel);}
  function done(){cleanup();resolve();}
  function cancel(){cleanup();reject(Error('WORKER_REQUEST_TIMEOUT'));}
  signal?.addEventListener('abort',cancel,{once:true});if(signal?.aborted)cancel();
 });
}
async function bytes(req,signal){
 if(req.method!=='POST'||!req.headers.get('content-type')?.startsWith('application/json'))throw Error('VALIDATION_ERROR');
 if(!req.body)throw Error('VALIDATION_ERROR');
 return readBoundedBytes(req,8192,{signal});
}
// Durable acknowledgement is stored by the server transaction before responding.
// All routes (including fault probes) authenticate the exact signed bytes first.
/**
 * @param {{env: {get(name: string): string | undefined} | Record<string, string | undefined>,
 * config?: typeof edgeConfiguration, fetchImpl?: typeof fetch, rpcFactory?: Function,
 * now?: () => number, wait?: (ms: number, signal?: AbortSignal) => Promise<void>, requestTimeoutMs?: number}} options
 */
export function createEdgeReceiver({env,config=edgeConfiguration,fetchImpl=fetch,rpcFactory,now=()=>Math.floor(Date.now()/1000),wait=waitWithinBudget,requestTimeoutMs=65000}){
 if(!Number.isSafeInteger(requestTimeoutMs)||requestTimeoutMs<1||requestTimeoutMs>65000)throw Error('WORKER_CONFIGURATION_INVALID');
 return async req=>{
  let key;
  try{
   const route=edgeRoute(req.url,config.receiverUrl.slice(0,-'/accept'.length),['/accept','/redirect','/timeout','/reject']);
   if(route===null)return reply(404,{code:'NOT_FOUND'});
   const mode=route.slice(1);
   const eventId=req.headers.get('x-jentra-event-id'),timestamp=req.headers.get('x-jentra-timestamp'),signature=req.headers.get('x-jentra-signature');
   const match=/^v([12])=([a-f0-9]{64})$/.exec(signature??'');
   if(!uuid.test(eventId??'')||!/^\d{10}$/.test(timestamp??'')||!match||Number(timestamp)>now()+30||Number(timestamp)<now()-300)return reply(403,{code:'INTEGRATION_ACCESS_DENIED'});
   const budget=AbortSignal.any([req.signal,AbortSignal.timeout(requestTimeoutMs)]);
   const payload=await bytes(req,budget),event=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(payload));
   // Strict schema and exact serialization. Signed whitespace/alternate key order
   // never become a second accepted representation of the committed event.
   if(!event||typeof event!=='object'||Array.isArray(event)||event.eventId!==eventId||!forecastEvent(event,event).equals(payload))return reply(400,{code:'EVENT_CONTRACT_MISMATCH'});
   if(value(env,'SUPABASE_URL')!==config.url)throw Error('WORKER_PROVIDER_UNAVAILABLE');
   const serviceKey=value(env,'SUPABASE_SERVICE_ROLE_KEY');
   if(serviceCredentialKind(serviceKey)===null)throw Error('WORKER_PROVIDER_UNAVAILABLE');
   const boundedFetch=(url,options={})=>fetchImpl(url,{...options,signal:options.signal?AbortSignal.any([options.signal,budget]):budget});
   const rpc=rpcFactory?rpcFactory({url:config.url,serviceKey,fetchImpl:boundedFetch}):createWorkerRpc({url:config.url,serviceKey,fetchImpl:boundedFetch});
   const edge=(action,p)=>rpc('wave5_edge_control',{p_runtime_id:config.runtimeId,p_action:action,p_payload:p});
   const answer=await edge('key',{ref:`w5/runtime/20261008/delivery/v${match[1]}`});
   if(!hex.test(answer?.value??''))throw Error('WORKER_PROVIDER_UNAVAILABLE');
   key=Buffer.from(answer.value,'hex');
   const signed=signDelivery({payload,eventId,timestamp:Number(timestamp),key,keyVersion:Number(match[1])});
   if(!timingSafeEqual(Buffer.from(signed),Buffer.from(signature)))return reply(403,{code:'INTEGRATION_ACCESS_DENIED'});
   // Server rechecks live scope, immutable committed outbox/source and active
   // subscription/key version before any receipt or fault response.
   const result=await edge(mode==='accept'||mode==='timeout'?'receive':'receive_probe',{
    event,keyVersion:Number(match[1]),payloadBase64:payload.toString('base64'),sha256:createHash('sha256').update(payload).digest('hex'),timestamp:Number(timestamp),mode,
   });
   if(result?.acknowledged!==true&&result?.permitted!==true)throw Error('WORKER_PROVIDER_UNAVAILABLE');
   if(mode==='redirect')return reply(307,{code:'REDIRECT_PROBE'},{location:config.receiverUrl});
   if(mode==='reject')return reply(503,{code:'RECEIVER_PROBE_REJECTED'});
   if(mode==='timeout')await wait(12000,budget);
   if(budget.aborted)throw Error('WORKER_REQUEST_TIMEOUT');
   return reply(200,{eventId,sha256:result.sha256,duplicate:result.duplicate===true,acknowledged:true});
  }catch(error){
   if(error.message==='WORKER_REQUEST_TIMEOUT')return reply(408,{code:'REQUEST_TIMEOUT'});
   return reply(error instanceof SyntaxError||/VALIDATION|JSON|utf-8|WORKER_OUTPUT_LIMIT/.test(error.message)?400:503,{code:'RECEIVER_UNAVAILABLE'});
  }
  finally {key?.fill(0);}
 };
}
