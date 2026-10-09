import {createHash,timingSafeEqual} from 'node:crypto';
import {Buffer} from 'node:buffer';
import {createWorkerRpc} from './persistent_control.mjs';
import {forecastEvent,signDelivery} from './integration_policy.mjs';
import {edgeConfiguration} from './edge_configuration.mjs';

const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;
const hex=/^[a-f0-9]{64}$/;
const reply=(status,body,headers={})=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json','cache-control':'no-store',...headers}});
const value=(env,name)=>typeof env.get==='function'?env.get(name):env[name];
async function bytes(req){
 if(req.method!=='POST'||!req.headers.get('content-type')?.startsWith('application/json'))throw Error('VALIDATION_ERROR');
 const reader=req.body?.getReader();if(!reader)throw Error('VALIDATION_ERROR');
 const chunks=[];let size=0;
 try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>8192)throw Error('VALIDATION_ERROR');chunks.push(Buffer.from(value));}}
 catch(error){await reader.cancel().catch(()=>{});throw error;}finally{reader.releaseLock();}
 return Buffer.concat(chunks);
}
// Durable acknowledgement is stored by the server transaction before responding.
// All routes (including fault probes) authenticate the exact signed bytes first.
/**
 * @param {{env: {get(name: string): string | undefined} | Record<string, string | undefined>,
 * config?: typeof edgeConfiguration, fetchImpl?: typeof fetch, rpcFactory?: Function,
 * now?: () => number, wait?: (ms: number) => Promise<void>}} options
 */
export function createEdgeReceiver({env,config=edgeConfiguration,fetchImpl=fetch,rpcFactory,now=()=>Math.floor(Date.now()/1000),wait=ms=>new Promise(r=>setTimeout(r,ms))}){
 return async req=>{
  let key;
  try{
   const url=new URL(req.url),expected=new URL(config.receiverUrl),prefix=expected.pathname.slice(0,-'accept'.length);
   const mode=url.pathname.slice(prefix.length);
   if(url.origin!==expected.origin||url.search||!url.pathname.startsWith(prefix)||!['accept','redirect','timeout','reject'].includes(mode))return reply(404,{code:'NOT_FOUND'});
   const eventId=req.headers.get('x-jentra-event-id'),timestamp=req.headers.get('x-jentra-timestamp'),signature=req.headers.get('x-jentra-signature');
   const match=/^v([12])=([a-f0-9]{64})$/.exec(signature??'');
   if(!uuid.test(eventId??'')||!/^\d{10}$/.test(timestamp??'')||!match||Number(timestamp)>now()+30||Number(timestamp)<now()-300)return reply(403,{code:'INTEGRATION_ACCESS_DENIED'});
   const payload=await bytes(req),event=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(payload));
   // Strict schema and exact serialization. Signed whitespace/alternate key order
   // never become a second accepted representation of the committed event.
   if(!event||typeof event!=='object'||Array.isArray(event)||event.eventId!==eventId||!forecastEvent(event,event).equals(payload))return reply(400,{code:'EVENT_CONTRACT_MISMATCH'});
   if(value(env,'SUPABASE_URL')!==config.url)throw Error('WORKER_PROVIDER_UNAVAILABLE');
   const serviceKey=value(env,'SUPABASE_SERVICE_ROLE_KEY');
   if(!/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(serviceKey??''))throw Error('WORKER_PROVIDER_UNAVAILABLE');
   const rpc=rpcFactory?rpcFactory({url:config.url,serviceKey,fetchImpl}):createWorkerRpc({url:config.url,serviceKey,fetchImpl});
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
   if(mode==='timeout')await wait(12000);
   return reply(200,{eventId,sha256:result.sha256,duplicate:result.duplicate===true,acknowledged:true});
  }catch(error){return reply(error instanceof SyntaxError||/VALIDATION|JSON|utf-8/.test(error.message)?400:503,{code:'RECEIVER_UNAVAILABLE'});}
  finally {key?.fill(0);}
 };
}
