import {createHash,createHmac,randomUUID,timingSafeEqual} from 'node:crypto';
import {Buffer} from 'node:buffer';

const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PROJECT='https://xpdoufauvrbdmxgngetv.supabase.co';
const ORIGIN='https://jentra-os-sales.web.app';
const EMAIL=/^[^\s\r\n<>@]+@[^\s\r\n<>@]+\.[^\s\r\n<>@]+$/;
export class MailFailure extends Error {constructor(code){super(code);this.code=code;}}
const requireValue=(condition,code)=>{if(!condition)throw new MailFailure(code);};
const escaped=s=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');

// Domain-separated, reproducible secrets survive a worker restart without
// storing plaintext tokens/codes in a queue, log, application or database.
export function deriveMailSecret(job,key){
 requireValue(UUID.test(job.id)&&UUID.test(job.tenant_id)&&UUID.test(job.challenge_id),'MAIL_JOB_INVALID');
 requireValue(typeof key==='string'&&/^[0-9a-f]{64}$/.test(key),'MAIL_KEY_MISSING');
 requireValue(createHash('sha256').update(Buffer.from(key,'hex')).digest('hex')===job.snapshot.secret_key_sha256,'MAIL_KEY_CHANGED');
 requireValue(['order_link','order_code','delivery_link','delivery_code'].includes(job.kind),'MAIL_PURPOSE_INVALID');
 const hex=createHmac('sha256',Buffer.from(key,'hex')).update(JSON.stringify([
  'jentra-sales-mail-v1',job.tenant_id,job.id,job.challenge_id,job.kind,job.snapshot.key_version,
 ])).digest('hex');
 return job.kind.endsWith('_link')?hex:(BigInt('0x'+hex)%1000000n).toString().padStart(6,'0');
}
export function renderMail(job,secret){
 const p=job.snapshot;
 requireValue(p?.template==='v1'&&p.provider==='resend'&&p.origin===ORIGIN,'MAIL_POLICY_INVALID');
 requireValue(EMAIL.test(p.sender)&&EMAIL.test(p.recipient)&&p.sender.length<=254&&p.recipient.length<=254,'MAIL_ADDRESS_INVALID');
 requireValue(typeof p.organization==='string'&&p.organization.length>0&&p.organization.length<=200
  &&!/[\r\n\0]/.test(p.organization)&&Number.isFinite(Date.parse(p.expires_at)),'MAIL_TEMPLATE_INVALID');
 const link=job.kind.endsWith('_link'),delivery=job.kind.startsWith('delivery_');
 const url=link?`${ORIGIN}/#${delivery?'delivery':'confirm'}=${secret}`:null;
 const text=link
  ? `${p.organization} requests your response to ${delivery?'posted delivery quantities':'an approved order'}.\n\nOpen ${url}\n\nThis link expires at ${p.expires_at}. Opening it records no decision. You will separately verify email access and review ${delivery?'received, refused and short quantities':'the terms'} before responding. If you did not expect this message, ignore it.`
  : `${p.organization} ${delivery?'delivery':'order'} verification code: ${secret}\n\nUse this code only on the Jentra Sales response page you opened. It expires at ${p.expires_at}. This code records no decision. Do not share it with a caller.`;
 return {from:`Jentra Sales <${p.sender}>`,to:[p.recipient],
  subject:link?(delivery?'Review delivery quantities':'Review an order request'):(delivery?'Your delivery verification code':'Your order verification code'),text,
  html:'<div style="font-family:system-ui,sans-serif;white-space:pre-line">'+escaped(text)+'</div>'};
}
export function createResendProvider({apiKey,fetchImpl=fetch}){
 requireValue(typeof apiKey==='string'&&apiKey.length>12,'MAIL_PROVIDER_KEY_MISSING');
 return Object.freeze({async send(job,message){
  let response;try{response=await fetchImpl('https://api.resend.com/emails',{
   method:'POST',redirect:'error',signal:AbortSignal.timeout(15000),
   headers:{Authorization:`Bearer ${apiKey}`,'Content-Type':'application/json',
    'Idempotency-Key':`jentra-sales/${job.tenant_id}/${job.id}/${job.kind}/v1`},body:JSON.stringify(message),
  });}catch{throw new MailFailure('MAIL_PROVIDER_UNCERTAIN');}
  requireValue(response.ok,'MAIL_PROVIDER_REJECTED');
  let value;try{value=await response.json();}catch{throw new MailFailure('MAIL_PROVIDER_UNCERTAIN');}
  requireValue(typeof value?.id==='string'&&UUID.test(value.id),'MAIL_PROVIDER_UNCERTAIN');
  return value.id;
 }});
}
export function createMailRpc({serviceKey,fetchImpl=fetch}){
 requireValue(typeof serviceKey==='string','MAIL_SERVICE_KEY_MISSING');
 const secretKey=/^sb_secret_[A-Za-z0-9_-]{10,}$/.test(serviceKey);
 let legacyRole;try{legacyRole=JSON.parse(Buffer.from(serviceKey.split('.')[1]??'','base64url').toString('utf8')).role;}catch{}
 requireValue(secretKey||(/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(serviceKey)&&legacyRole==='service_role'),'MAIL_SERVICE_KEY_INVALID');
 return async(name,params)=>{
  requireValue(['field_sales_mail_claim','field_sales_mail_step'].includes(name),'MAIL_RPC_FORBIDDEN');
  let response;try{response=await fetchImpl(`${PROJECT}/rest/v1/rpc/${name}`,{
   method:'POST',redirect:'error',signal:AbortSignal.timeout(15000),
   headers:{apikey:serviceKey,...(secretKey?{}:{Authorization:`Bearer ${serviceKey}`}), 'Content-Type':'application/json',
    'Content-Profile':'api','Accept-Profile':'api'},body:JSON.stringify(params),
  });}catch{throw new MailFailure('MAIL_RPC_UNCERTAIN');}
  requireValue(response.ok,'MAIL_RPC_REJECTED');
  try{return await response.json();}catch{throw new MailFailure('MAIL_RPC_UNCERTAIN');}
 };
}
export async function sendOne({tenantIds,rpc,providerKeys,secretKeys,providerFactory=createResendProvider,fetchImpl=fetch,now=Date.now}){
 requireValue(Array.isArray(tenantIds)&&tenantIds.length>0&&tenantIds.length<=100
  &&tenantIds.every(t=>typeof t==='string'&&UUID.test(t))&&new Set(tenantIds).size===tenantIds.length,'MAIL_TENANT_INVALID');
 const lease=randomUUID();
 const job=await rpc('field_sales_mail_claim',{p_tenant_ids:tenantIds,p_lease_id:lease});
 if(job?.state==='idle')return {state:'idle'};
 requireValue(job?.state==='claimed'&&tenantIds.includes(job.tenant_id)&&UUID.test(job.id),'MAIL_JOB_INVALID');
 const params={p_tenant_id:job.tenant_id,p_job_id:job.id,p_lease_id:lease};
 try{
  requireValue(Date.parse(job.snapshot?.expires_at)>now()+5000,'MAIL_JOB_EXPIRED');
  const secret=deriveMailSecret(job,secretKeys[job.snapshot.key_version]);
  const message=renderMail(job,secret);
  const provider=providerFactory({apiKey:providerKeys[job.snapshot.credential_alias],fetchImpl});
  const prepared=await rpc('field_sales_mail_step',{...params,p_action:'prepare',p_secret:secret});
  requireValue(prepared?.state==='prepared','MAIL_PREPARE_INVALID');
  const reference=await provider.send(job,message);
  const ack=await rpc('field_sales_mail_step',{...params,p_action:'ack',p_secret:secret,p_provider_reference:reference});
  requireValue(ack?.state==='provider_accepted','MAIL_ACK_UNCERTAIN');
  return {state:'provider_accepted',delivery:'not_established'};
 }catch(error){
  // Resend's 24-hour idempotency window exceeds the 15-minute challenge. An
  // explicit new claim retries the same frozen body/secret/key, never a new mail.
  try{await rpc('field_sales_mail_step',{...params,p_action:'defer'});}catch{}
  throw error instanceof MailFailure?error:new MailFailure('MAIL_SEND_UNCERTAIN');
 }
}
function json(value,status){return new Response(JSON.stringify(value),{status,headers:{'Content-Type':'application/json',
 'Cache-Control':'no-store','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff'}});}
export function createMailWorker({env,fetchImpl=fetch}){
 return async request=>{
  if(request.method!=='POST')return json({code:'METHOD_NOT_ALLOWED'},405);
  const expected=env.get('FIELD_SALES_MAIL_SCHEDULER_SECRET');
  const received=request.headers.get('Authorization')?.replace(/^Bearer /,'');
  if(typeof expected!=='string'||expected.length<32||typeof received!=='string'
   ||Buffer.byteLength(received)!==Buffer.byteLength(expected)
   ||!timingSafeEqual(Buffer.from(received),Buffer.from(expected)))return json({code:'UNAUTHORIZED'},401);
  if(env.get('FIELD_SALES_MAIL_ENABLED')!=='true')return json({code:'MAIL_DISABLED'},503);
  try{
   requireValue(env.get('SUPABASE_URL')===PROJECT,'MAIL_PROJECT_INVALID');
   const tenantIds=JSON.parse(env.get('FIELD_SALES_MAIL_TENANT_IDS')??'[]');
   // The deployment's private allowlist, then the database's oldest eligible
   // job, chooses an organization. Caller input never selects the tenant.
   if(request.body){const reader=request.body.getReader();let size=0;const chunks=[];try{
    for(;;){const {value,done}=await reader.read();if(done)break;size+=value.byteLength;
     if(size>128){await reader.cancel();throw new MailFailure('MAIL_BODY_FORBIDDEN');}chunks.push(value);}
   }finally{reader.releaseLock();}
    if(size>0){let body;try{body=JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{throw new MailFailure('MAIL_BODY_FORBIDDEN');}
     requireValue(body!==null&&typeof body==='object'&&!Array.isArray(body)&&Object.keys(body).length===0,'MAIL_BODY_FORBIDDEN');}}
   const providerKeys=JSON.parse(env.get('FIELD_SALES_MAIL_PROVIDER_KEYS')??'{}');
   const secretKeys=JSON.parse(env.get('FIELD_SALES_MAIL_SECRET_KEYS')??'{}');
   const databaseKeys=env.get('SUPABASE_SECRET_KEYS');
   const serviceKey=databaseKeys?JSON.parse(databaseKeys)[env.get('FIELD_SALES_MAIL_DATABASE_KEY_NAME')??'default']:env.get('SUPABASE_SERVICE_ROLE_KEY');
   const rpc=createMailRpc({serviceKey,fetchImpl});
   const result=await sendOne({tenantIds,rpc,providerKeys,secretKeys,fetchImpl});
   return json(result,200);
  }catch(error){return json({code:error instanceof MailFailure?error.code:'MAIL_CONFIGURATION_INVALID'},503);}
 };
}
