import {createServer} from 'node:http';
import {lookup} from 'node:dns/promises';
import {readFile} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {PersistentInvocationControl} from './persistent_control.mjs';
import {createScopedWorkerRpc} from './scoped_runtime.mjs';
import {createExternalCommandHandler,createReviewedModelHandler} from './worker_endpoints.mjs';
import {OpenAIResponsesProvider} from './openai_model_adapter.mjs';
import {pinnedHttpsPost} from './integration_policy.mjs';
import {runDeliverySchedule} from './delivery_schedule.mjs';
import {runSyntheticSubscriptionBatch} from './subscription_schedule.mjs';

export function validateBoundReview(review,approval){
 const {bundleSha256,...body}=review;
 if(createHash('sha256').update(JSON.stringify(body)).digest('hex')!==bundleSha256)throw Error('REVIEW_HASH_MISMATCH');
 if(approval?.approvedBundleSha256!==bundleSha256||approval?.ownerApproved!==true||!approval?.ownerMessageReference)throw Error('OWNER_APPROVAL_REQUIRED');
 const c=review.workerConfiguration;
 if(review.approvalReady!==true||!c.hostBinding.publicBaseUrl||!c.receiver.url)throw Error('RUNTIME_BINDINGS_REQUIRED');
 for(const v of [c.hostBinding.publicBaseUrl,c.receiver.url]){const u=new URL(v);if(u.protocol!=='https:'||u.username||u.password||u.hash||u.search||u.port&&u.port!=='443')throw Error('RUNTIME_BINDINGS_INVALID');}
 if(c.url!=='https://xpdoufauvrbdmxgngetv.supabase.co'||c.projectId!=='xpdoufauvrbdmxgngetv'||c.hostBinding.listenAddress!=='127.0.0.1'||c.hostBinding.port!==8785||
  c.receiver.allowedHosts.length!==1||c.receiver.allowedHosts[0]!==new URL(c.receiver.url).hostname||c.model.model!=='gpt-4.1-mini-2025-04-14')throw Error('RUNTIME_CONFIGURATION_INVALID');
 return c;
}
export async function verifyArtifactHashes(review,root){
 for(const a of [...review.migrations,...review.artifacts]){
  const bytes=await readFile(new URL(a.path,pathToFileURL(root.endsWith('/')?root:root+'/')));
  if(createHash('sha256').update(bytes).digest('hex')!==a.sha256)throw Error('RUNTIME_SOURCE_CHANGED');
 }
}
function secret(env,key){const v=env[key];if(typeof v!=='string'||v.length<32)throw Error('RUNTIME_SECRET_REQUIRED');return v;}
export async function startRuntime({review,approval,env=process.env,root,fetchImpl=fetch}){
 const c=validateBoundReview(review,approval);await verifyArtifactHashes(review,root);
 const serviceKey=secret(env,c.secrets.serviceKey);
 // Legacy service_role JWT is required by this transport. New sb_secret keys
 // cannot be used as Authorization bearer tokens. No key is discovered locally.
 if(!/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(serviceKey))throw Error('SERVICE_ROLE_JWT_REQUIRED');
 const control=new PersistentInvocationControl(createScopedWorkerRpc({runtimeId:c.runtimeId,url:c.url,serviceKey,fetchImpl}));
 const keyMap=new Map();for(const [ref,name] of Object.entries(c.secrets.deliveryKeys)){
  const value=secret(env,name);if(!/^[a-f0-9]{64}$/.test(value))throw Error('DELIVERY_KEY_CONFIGURATION_INVALID');keyMap.set(ref,Buffer.from(value,'hex'));}
 const vault={read:async ref=>{if(!keyMap.has(ref))throw Error('DELIVERY_KEY_UNAVAILABLE');return keyMap.get(ref);}};
 const providerReview={...c.model,approved:true};
 const provider=new OpenAIResponsesProvider({apiKey:secret(env,c.secrets.modelKey),review:providerReview,fetchImpl});
 const external=createExternalCommandHandler({control});
 const model=createReviewedModelHandler({control,provider,policy:providerReview,url:c.url,publishableKey:secret(env,c.secrets.publishableKey),fetchImpl});
 const abort=new AbortController();let active=0;
 const server=createServer(async(req,res)=>{
  if(active>=c.http.maxConcurrentRequests){res.writeHead(429,{'cache-control':'no-store'});res.end('{"code":"THROTTLED"}');return;}
  active++;try{
   if(req.method!=='POST'||!c.http.paths.includes(req.url)){res.writeHead(404);res.end();return;}
   const chunks=[];let size=0;for await(const chunk of req){size+=chunk.length;if(size>c.http.maxRequestBytes){res.writeHead(413);res.end();return;}chunks.push(chunk);}
   const request=new Request('https://runtime.invalid'+req.url,{method:'POST',headers:req.headers,body:Buffer.concat(chunks),signal:abort.signal});
   const response=await(req.url===c.http.paths[0]?external(request):model(request));res.writeHead(response.status,Object.fromEntries(response.headers));res.end(Buffer.from(await response.arrayBuffer()));
  }catch{if(!res.headersSent)res.writeHead(503,{'cache-control':'no-store'});res.end('{"code":"WORKER_PROVIDER_UNAVAILABLE"}');}finally{active--;}
 });
 server.requestTimeout=15000;server.headersTimeout=10000;server.maxHeadersCount=32;
 await control.readiness();
 await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(c.hostBinding.port,c.hostBinding.listenAddress,resolve);});
 const report=()=>{}; // No headers, bodies, secrets or JWTs enter logs.
 const tasks=[runDeliverySchedule({control,vault,resolve:host=>lookup(host,{all:true}),post:pinnedHttpsPost,intervalMs:c.schedulers.deliveryIntervalMs,
  limit:c.schedulers.deliveryBatchLimit,signal:abort.signal,onResult:report})];
 const tick=async(fn,interval)=>{while(!abort.signal.aborted){try{await fn();}catch{}await new Promise(resolve=>{
  const timer=setTimeout(done,interval);function done(){clearTimeout(timer);abort.signal.removeEventListener('abort',done);resolve();}
  abort.signal.addEventListener('abort',done,{once:true});if(abort.signal.aborted)done();});}};
 tasks.push(tick(()=>runSyntheticSubscriptionBatch({control,limit:50,signal:abort.signal}),c.schedulers.subscriptionIntervalMs));
 tasks.push(tick(()=>control.collectHealth(randomUUID(),c.permittedScope.tenantId),c.schedulers.healthIntervalMs));
 return {stop:async()=>{abort.abort();server.closeAllConnections();await new Promise(resolve=>server.close(resolve));await Promise.allSettled(tasks);
  for(const key of keyMap.values())key.fill(0);keyMap.clear();}};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 if(process.argv[2]!=='--serve'){process.stdout.write('Prepared launcher; --serve requires exact bound review, owner approval and injected secrets.\n');}
 else{
  try{const review=JSON.parse(await readFile(process.argv[3],'utf8')),approval=JSON.parse(await readFile(process.argv[4],'utf8'));
   const runtime=await startRuntime({review,approval,root:process.argv[5]});process.stdout.write('Scoped synthetic runtime started.\n');
   process.once('SIGINT',()=>runtime.stop());process.once('SIGTERM',()=>runtime.stop());
  }catch{process.stderr.write('Runtime refused: bound review, approval, source or private configuration is missing/invalid.\n');process.exitCode=1;}
 }
}
