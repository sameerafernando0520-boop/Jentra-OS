import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {deriveMailSecret,renderMail,sendOne,createMailWorker,createMailRpc,createResendProvider} from './mail_worker.mjs';
const key='a'.repeat(64),tenant=randomUUID(),otherTenant=randomUUID();
const job={state:'claimed',id:randomUUID(),tenant_id:tenant,challenge_id:randomUUID(),kind:'order_link',snapshot:{
 template:'v1',provider:'resend',origin:'https://jentra-os-sales.web.app',key_version:'v1',credential_alias:'platform',
 secret_key_sha256:createHash('sha256').update(Buffer.from(key,'hex')).digest('hex'),
 sender:'sales@example.invalid',recipient:'buyer@example.invalid',organization:'Customer Organization <1>',expires_at:'2030-01-01T00:00:00Z',
}};
const options={tenantIds:[tenant,otherTenant],providerKeys:{platform:'private-provider-key'},secretKeys:{v1:key}};
const databaseKey='sb_secret_synthetic_test_key_only';
test('secrets are stable after restart and separate across organizations and purposes',()=>{
 const secret=deriveMailSecret(job,key);
 assert.equal(deriveMailSecret(structuredClone(job),key),secret);assert.match(secret,/^[0-9a-f]{64}$/);
 assert.notEqual(deriveMailSecret({...job,tenant_id:otherTenant},key),secret);
 const code=deriveMailSecret({...job,kind:'order_code'},key);assert.match(code,/^\d{6}$/);assert.notEqual(code,secret);
 assert.throws(()=>deriveMailSecret(job,'b'.repeat(64)),/MAIL_KEY_CHANGED/);
});
test('organization text is escaped and exact link/code templates never contain commercial data',()=>{
 const message=renderMail(job,deriveMailSecret(job,key));
 assert.ok(message.text.includes('https://jentra-os-sales.web.app/#confirm='));
 assert.ok(message.html.includes('&lt;1&gt;'));assert.ok(!message.html.includes('<1>'));
 assert.ok(!message.text.includes('grand_total'));assert.equal(message.to.length,1);
 assert.throws(()=>renderMail({...job,snapshot:{...job.snapshot,origin:'https://foreign.invalid'}},'token'),/MAIL_POLICY_INVALID/);
 assert.throws(()=>renderMail({...job,snapshot:{...job.snapshot,recipient:'buyer@example.invalid\r\nBcc:x@x.invalid'}},'token'),/MAIL_ADDRESS_INVALID/);
});
test('provider and acknowledgement retries keep the exact frozen message and idempotency key',async()=>{
 const sends=[],steps=[];let ackLost=true;
 const rpc=async(name,p)=>{steps.push([name,p]);if(name==='field_sales_mail_claim')return structuredClone(job);
  if(p.p_action==='prepare')return {state:'prepared'};
  if(p.p_action==='ack'){if(ackLost){ackLost=false;throw Error('transport interrupted');}return {state:'provider_accepted'};}
  return {state:'deferred'};};
 const fetchImpl=async(url,init)=>{sends.push([url,init]);return Response.json({id:'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa'});};
 await assert.rejects(()=>sendOne({...options,rpc,fetchImpl}),/MAIL_SEND_UNCERTAIN/);
 assert.deepEqual(await sendOne({...options,rpc,fetchImpl}),{state:'provider_accepted',delivery:'not_established'});
 assert.equal(sends.length,2);assert.equal(sends[0][1].body,sends[1][1].body);
 assert.equal(sends[0][1].headers['Idempotency-Key'],sends[1][1].headers['Idempotency-Key']);
 assert.equal(steps.filter(([,p])=>p.p_action==='prepare')[0][1].p_secret,deriveMailSecret(job,key));
});
test('wrong tenant and missing/changed server keys prevent preparation and provider calls',async()=>{
 let prepares=0,sends=0;
 const rpc=async(name,p)=>{if(name==='field_sales_mail_claim')return {...job,tenant_id:randomUUID()};if(p.p_action==='prepare')prepares++;};
 await assert.rejects(()=>sendOne({...options,rpc,providerFactory:()=>{sends++;}}),/MAIL_JOB_INVALID/);
 assert.equal(prepares,0);assert.equal(sends,0);
 await assert.rejects(()=>sendOne({...options,secretKeys:{v1:'b'.repeat(64)},rpc:async name=>name==='field_sales_mail_claim'?job:{state:'deferred'},providerFactory:()=>{sends++;}}),/MAIL_KEY_CHANGED/);
 assert.equal(sends,0);
});
test('HTTP sender uses only the fixed provider origin and original key; response errors are redacted',async()=>{
 let request;
 const provider=createResendProvider({apiKey:'private-provider-key',fetchImpl:async(url,init)=>{request={url,init};return Response.json({id:randomUUID()});}});
 await provider.send(job,renderMail(job,deriveMailSecret(job,key)));
 assert.equal(request.url,'https://api.resend.com/emails');assert.equal(request.init.redirect,'error');
 assert.equal(request.init.headers['Idempotency-Key'],`jentra-sales/${tenant}/${job.id}/order_link/v1`);
 const failing=createResendProvider({apiKey:'private-provider-key',fetchImpl:async()=>new Response('private provider diagnostic',{status:400})});
 await assert.rejects(()=>failing.send(job,{}),e=>e.code==='MAIL_PROVIDER_REJECTED'&&!e.message.includes('private'));
});
test('service transport never exposes the private schema or calls arbitrary RPCs',async()=>{
 const calls=[];
 const rpc=createMailRpc({serviceKey:databaseKey,fetchImpl:async(url,init)=>{calls.push([url,init]);return Response.json({state:'idle'});}});
 await rpc('field_sales_mail_claim',{p_tenant_ids:[tenant],p_lease_id:randomUUID()});
 assert.equal(calls[0][1].headers['Content-Profile'],'api');
 assert.equal(calls[0][1].headers.apikey,databaseKey);assert.equal(calls[0][1].headers.Authorization,undefined);
 await assert.rejects(()=>rpc('confirmation_dispatch',{}),/MAIL_RPC_FORBIDDEN/);assert.equal(calls.length,1);
});
test('worker denies GET, missing scheduler authority and default-disabled sending without I/O',async()=>{
 let calls=0;const values=new Map([['FIELD_SALES_MAIL_SCHEDULER_SECRET','s'.repeat(40)]]);
 const handler=createMailWorker({env:{get:k=>values.get(k)},fetchImpl:async()=>{calls++;throw Error('must not send');}});
 assert.equal((await handler(new Request('https://worker.invalid'))).status,405);
 assert.equal((await handler(new Request('https://worker.invalid',{method:'POST'}))).status,401);
 const disabled=await handler(new Request('https://worker.invalid',{method:'POST',headers:{Authorization:'Bearer '+'s'.repeat(40)}}));
 assert.equal(disabled.status,503);assert.deepEqual(await disabled.json(),{code:'MAIL_DISABLED'});assert.equal(calls,0);
});
test('delivery purpose has distinct bearer material and does not render an order response link',()=>{
 const delivery={...job,kind:'delivery_link'};
 assert.notEqual(deriveMailSecret(delivery,key),deriveMailSecret(job,key));
 const mail=renderMail(delivery,deriveMailSecret(delivery,key));
 assert.ok(mail.text.includes('#delivery='));assert.ok(!mail.text.includes('#confirm='));
 assert.ok(mail.text.includes('received, refused and short quantities'));
 assert.match(deriveMailSecret({...delivery,kind:'delivery_code'},key),/^\d{6}$/);
});
test('scheduler body cannot choose an organization and ordinary empty JSON is allowed',async()=>{
 const values=new Map([['FIELD_SALES_MAIL_SCHEDULER_SECRET','s'.repeat(40)],['FIELD_SALES_MAIL_ENABLED','true'],
  ['SUPABASE_URL','https://xpdoufauvrbdmxgngetv.supabase.co'],['SUPABASE_SECRET_KEYS',JSON.stringify({default:databaseKey})],
  ['FIELD_SALES_MAIL_TENANT_IDS',JSON.stringify([tenant])]]);
 const calls=[];
 const handler=createMailWorker({env:{get:k=>values.get(k)},fetchImpl:async(url,init)=>{calls.push([url,init]);return Response.json({state:'idle'});}});
 const init={method:'POST',headers:{Authorization:'Bearer '+'s'.repeat(40)}};
 const blocked=await handler(new Request('https://worker.invalid',{...init,body:JSON.stringify({tenant_ids:[otherTenant]})}));
 assert.equal(blocked.status,503);assert.equal(calls.length,0);
 const idle=await handler(new Request('https://worker.invalid',{...init,body:'{}'}));assert.equal(idle.status,200);
 assert.deepEqual(JSON.parse(calls[0][1].body).p_tenant_ids,[tenant]);
});

test('legacy service JWT remains supported and public keys cannot become worker credentials',async()=>{
 const jwt=role=>Buffer.from('{"alg":"HS256"}').toString('base64url')+'.'+Buffer.from(JSON.stringify({role})).toString('base64url')+'.synthetic_signature';
 let headers;const legacy=jwt('service_role');
 await createMailRpc({serviceKey:legacy,fetchImpl:async(_url,init)=>{headers=init.headers;return Response.json({state:'idle'});}})('field_sales_mail_claim',{});
 assert.equal(headers.Authorization,'Bearer '+legacy);
 for(const publicKey of ['sb_publishable_synthetic_test_key',jwt('anon'),'arbitrary-private-looking-string'])
  assert.throws(()=>createMailRpc({serviceKey:publicKey}),/MAIL_SERVICE_KEY_INVALID/);
});
